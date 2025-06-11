using System;
using System.Collections;
using BeefParser;
using BeefParser.AST;
using System.Diagnostics;

using internal BeefParser;

namespace BeefYield
{
	public class FrameGenVisitor : ASTVisitor
	{
		private Dictionary<StringView, TypeSpec> mVariables = new .() ~ Release!(_);
		private Dictionary<int, Frame> mFrames = new .() ~ Release!(_);
		private int mGroupCounter;
		private int mFrameCounter;
		private int mReservedFrameCounter;
		private List<Frame> mFrameStack = new .() ~ Release!(_);

		private Frame CurrentFrame => !mFrameStack.IsEmpty ? mFrameStack.Back : null;
		
		public Dictionary<StringView, TypeSpec> Variables => mVariables;
		public Dictionary<int, Frame> Frames => mFrames;

		public this()
		{
			mGroupCounter = 1;
			mFrameCounter = 0;
			mFrameStack.Add(newFrame("start"));
		}

		public void Clear()
		{
			Release!(mVariables, DictionaryReleaseKind.Items);
			mVariables.Clear();
			Release!(mFrames, DictionaryReleaseKind.Items);
			mFrames.Clear();

			mGroupCounter = 1;
			mFrameCounter = 0;
			mFrameStack.Add(newFrame("start"));
		}

		private Frame newFrame(String name)
		{
			Frame frame = new Frame(name, null, mFrameCounter++);
			mFrames.Add(frame.Id, frame);
			return frame;
		}

		private Frame newFrame(String name, String description, params Span<Object> args)
		{
			String desc = new .();
			if (args.IsEmpty)
				desc.Append(description);
			else
				desc.AppendF(description, params args);
			Frame frame = new Frame(name, desc, mFrameCounter++);
			mFrames.Add(frame.Id, frame);
			return frame;
		}

		private Frame reserveFrame(String name, String description, params Span<Object> args)
		{
			String desc = new .();
			if (args.IsEmpty)
				desc.Append(description);
			else
				desc.AppendF(description, params args);
			Frame frame = new Frame(name, desc, -(++mReservedFrameCounter));
			mFrames.Add(frame.Id, frame);
			return frame;
		}

		private void addReservedFrame(Frame frame)
		{
			Runtime.Assert(frame.Id < 0);
			Runtime.Assert(mFrames.Remove(frame.Id));
			frame.[Friend]Id = mFrameCounter++;
			mFrames.Add(frame.Id, frame);
		}

		private bool deleteFrame(Frame frame)
		{
			defer delete frame;
			return mFrames.Remove(frame.Id);
		}

		private Frame findFrame(String name)
		{
			for (let frame in mFrameStack.Reversed)
			{
				if (frame.Name == name)
					return frame;
			}
			return null;
		}
		
		/// This will discard the VisitResult!
		public new void Visit(ASTNode node)
		{
			node.Accept(this);
		}

		public override VisitResult Visit(CompoundStmt compStmt)
		{
			for (let ast in compStmt.Statements)
			{
				Visit(ast);
				if (CurrentFrame.Exit == .Return)
					return .Continue;
			}
			return .Continue;
		}

		public override VisitResult Visit(DoStmt node)
		{
			Runtime.NotImplemented();
		}

		public override VisitResult Visit(UsingStmt node)
		{
			Runtime.NotImplemented();
		}

		public override VisitResult Visit(IfStmt node)
		{
			int gid = mGroupCounter++;
			Frame initialFrame = CurrentFrame;
			int index = initialFrame.Statements.Count;

			// 1.
			// Visit ThenStatement on the current frame.
			// Unlike the loops, we don't need a separate frame for the 'if' parts.
			Visit(node.ThenStatement);

			if (CurrentFrame != initialFrame || CurrentFrame.Exit != .Continue)
			{
				Frame thenFrame = CurrentFrame;

				Frame elseFrame = null;
				Frame elseFrameTail = null;
				if (node.ElseStatement != null)
				{
					elseFrame = newFrame("block", $"if.else [{gid}]");
					mFrameStack.Add(elseFrame);
					Visit(node.ElseStatement);
					elseFrameTail = CurrentFrame;

					while (CurrentFrame != thenFrame)
					{
						let frame = mFrameStack.PopBack();
						for (let statement in frame.Finalizers)
							elseFrameTail.Statements.Add(statement);
					}
				}

				Frame afterFrame = newFrame("block", $"if.out [{gid}]");
				initialFrame.Statements.Insert(index,
					$"""
					if (!({node.Condition}))
					{{
						state = {elseFrame?.Id ?? afterFrame.Id};
						break;
					}}
					""");

				// Both the 'then' and the tail of the 'else' frame jumps to after the if
				if (thenFrame.Exit == .Continue)
					thenFrame.Next = afterFrame;
				if (elseFrameTail?.Exit == .Continue)
					elseFrameTail?.Next = afterFrame;

				while (CurrentFrame != initialFrame)
				{
					let frame = mFrameStack.PopBack();
					for (let statement in frame.Finalizers)
						thenFrame.Statements.Add(statement);
				}

				mFrameStack.Add(afterFrame);

				return .Continue;
			}

			// 2. (OPTIMIZATION)
			// ThenStatement has a flat control-flow.
			// Remove ThenStatement from the current frame and Visit ElseStatement this time, again, without making a new frame.
			var nodeCount = CurrentFrame.Statements.Count - index;
			if (nodeCount > 0)
				CurrentFrame.Statements.RemoveRange(index, nodeCount);

			if (node.ElseStatement != null)
			{
				index = initialFrame.Statements.Count;

				Visit(node.ElseStatement);

				if (CurrentFrame != initialFrame || CurrentFrame.Exit != .Continue)
				{
					Frame elseFrame = CurrentFrame;

					Frame afterFrame = newFrame("block", $"if.out [{gid}]");

					// NOTE: We already know the control-flow of the ThenStatement is flat, so it's okay to add it directly here.
					initialFrame.Statements.Insert(index,
						$"""
						if ({node.Condition})
						{{
							{node.ThenStatement}
							state = {afterFrame.Id};
							break;
						}}
						""");
					
					// The frame in which the ElseStatement was visited jumps to after the if
					elseFrame.Next = afterFrame;

					mFrameStack.Add(afterFrame);

					return .Continue;
				}

				nodeCount = CurrentFrame.Statements.Count - index;
				if (nodeCount > 0)
					CurrentFrame.Statements.RemoveRange(index, nodeCount);
			}
			
			// 3. (OPTIMIZATION)
			// This means the flow of this statement is straightforward (flat),
			// so the statement can be directly appended to the current frame without needing additional frames.
			CurrentFrame.Statements.Add(node);
			return .Continue;
		}

		public override VisitResult Visit(SwitchStmt node)
		{
			Runtime.NotImplemented();
		}

		public override VisitResult Visit(ForStmt node)
		{
			int gid = mGroupCounter++;
			Frame initialFrame = CurrentFrame;

			Frame afterFrame = reserveFrame("exit_block", $"for.out [{gid}]");
			mFrameStack.Add(afterFrame);

			Frame incFrame = reserveFrame("loop_inc", $"for.inc [{gid}]");
			mFrameStack.Add(incFrame);

			Frame bodyFrame = newFrame("block", $"for.body [{gid}]");
			mFrameStack.Add(bodyFrame);
			
			Visit(node.Body);

			if (bodyFrame != CurrentFrame || CurrentFrame.Exit != .Continue)
			{
				Frame bodyFrameTail = CurrentFrame;

				// The initialFrame should jump to the loop frame.
				initialFrame.Next = bodyFrame;

				if (node.Declaration != null)
				{
					for (let variable in node.Declaration.Variables)
					{
						if (!mVariables.ContainsKey(variable.Name))
						{
							mVariables.Add(variable.Name, node.Declaration.Specification);
						}
						else
						{
							Debug.WriteLine($"Warning! Duplicate var \"{variable.Name}\" ignored!");
						}

						initialFrame.Statements.Add($"{variable.Name} = {variable.Initializer};");
					}
				}
				
				// Add statements to run the incrementors for the next iteration.
				addReservedFrame(incFrame);
				for (let incrementator in node.Incrementors)
					incFrame.Statements.Add(new ExpressionStmt() { Expr = incrementator });
				
				addReservedFrame(afterFrame);
				bodyFrame.Statements.Insert(0,
					$"""
					if (!({node.Condition}))
					{{
						state = {afterFrame.Id};
						break;
					}}
					""");
				
				// The tail frame jumps to the head for the loop continuation
				bodyFrameTail.Next = incFrame;
				incFrame.Next = bodyFrame;

				while (CurrentFrame != afterFrame)
				{
					let frame = mFrameStack.PopBack();
					for (let statement in frame.Finalizers)
						afterFrame.Statements.Insert(@statement.Index, statement);
				}
			}
			else
			{
				// (OPTIMIZATION)
				// This means the flow of this statement is straightforward (flat),
				// so the statement can be directly appended to the current frame without needing additional frames.
				deleteFrame(bodyFrame);
				while (CurrentFrame != initialFrame)
					mFrameStack.PopBack();
				initialFrame.Statements.Add(node);
			}

			return .Continue;
		}

		public override VisitResult Visit(ForeachStmt node)
		{
			int gid = mGroupCounter++;
			Frame initialFrame = CurrentFrame;
			
			Frame afterFrame = reserveFrame("exit_block", $"foreach.out [{gid}]");
			mFrameStack.Add(afterFrame);

			Frame incFrame = reserveFrame("loop_inc", $"foreach.inc [{gid}]");
			mFrameStack.Add(incFrame);

			Frame bodyFrame = newFrame("block", $"foreach.body [{gid}]");
			mFrameStack.Add(bodyFrame);

			bodyFrame.Finalizers.Add(
				"""
				if (CheckTypeNoWarn!<System.IDisposable>(_enumerator)) [ConstSkip]
				{
					_enumerator.Dispose();
				}
				""");
			
			Visit(node.Body);

			if (bodyFrame != CurrentFrame || CurrentFrame.Exit != .Continue)
			{
				Frame bodyFrameTail = CurrentFrame;

				// The initialFrame should jump to the loop frame.
				initialFrame.Next = bodyFrame;
				
				if (!mVariables.ContainsKey("_enumerator"))
				{
					mVariables.Add("_enumerator", new ExprModTypeSpec() { Type = .DeclType, Expr = node.SourceExpr });
				}
				else
				{
					Debug.WriteLine($"Warning! Duplicate var \"_enumerator\" ignored!");
				}

				initialFrame.Statements.Add($"_enumerator = {node.SourceExpr};");

				if (!mVariables.ContainsKey(node.TargetName))
				{
					let genericName = new GenericName() { Identifier = "Result" };
					genericName.TypeArguments.Add(node.TargetType);
					mVariables.Add(node.TargetName, genericName);
				}
				else
				{
					Debug.WriteLine($"Warning! Duplicate var \"{node.TargetName}\" ignored!");
				}

				initialFrame.Statements.Add($"{node.TargetName} = _enumerator.GetNext();");

				// Add statement to get the next item for the next iteration.
				addReservedFrame(incFrame);
				incFrame.Statements.Add($"{node.TargetName} = _enumerator.GetNext();");
				
				addReservedFrame(afterFrame);
				bodyFrame.Statements.Insert(0,
					$"""
					if (!({node.TargetName} case .Ok))
					{{
						state = {afterFrame.Id};
						break;
					}}
					""");
				
				// The tail frame jumps to the head for the loop continuation
				bodyFrameTail.Next = incFrame;
				incFrame.Next = bodyFrame;

				while (CurrentFrame != afterFrame)
				{
					let frame = mFrameStack.PopBack();
					for (let statement in frame.Finalizers)
						afterFrame.Statements.Insert(@statement.Index, statement);
				}
			}
			else
			{
				// (OPTIMIZATION)
				// This means the flow of this statement is straightforward (flat),
				// so the statement can be directly appended to the current frame without needing additional frames.
				deleteFrame(bodyFrame);
				while (CurrentFrame != initialFrame)
					mFrameStack.PopBack();
				initialFrame.Statements.Add(node);
			}

			return .Continue;
		}

		public override VisitResult Visit(WhileStmt node)
		{
			int gid = mGroupCounter++;
			Frame initialFrame = CurrentFrame;
			
			Frame afterFrame = reserveFrame("exit_block", $"while.out [{gid}]");
			mFrameStack.Add(afterFrame);

			Frame bodyFrame = newFrame("block", $"while.body [{gid}]");
			mFrameStack.Add(bodyFrame);
			
			Visit(node.Body);

			if (bodyFrame != CurrentFrame || CurrentFrame.Exit != .Continue)
			{
				Frame bodyFrameTail = CurrentFrame;

				// The initialFrame should jump to the loop frame.
				initialFrame.Next = bodyFrame;
				
				addReservedFrame(afterFrame);
				bodyFrame.Statements.Insert(0,
					$"""
					if (!({node.Condition}))
					{{
						state = {afterFrame.Id};
						break;
					}}
					""");

				// The tail frame jumps to the head for the loop continuation
				bodyFrameTail.Next = bodyFrame;

				while (CurrentFrame != afterFrame)
				{
					let frame = mFrameStack.PopBack();
					for (let statement in frame.Finalizers)
						afterFrame.Statements.Insert(@statement.Index, statement);
				}
			}
			else
			{
				// (OPTIMIZATION)
				// This means the flow of this statement is straightforward (flat),
				// so the statement can be directly appended to the current frame without needing additional frames.
				deleteFrame(bodyFrame);
				while (CurrentFrame != initialFrame)
					mFrameStack.PopBack();
				initialFrame.Statements.Add(node);
			}

			return .Continue;
		}

		public override VisitResult Visit(RepeatStmt node)
		{
			Runtime.NotImplemented();
		}

		public override VisitResult Visit(DeferStmt node)
		{
			CurrentFrame.Next = newFrame("block", $"defer [{mGroupCounter - 1}]");
			mFrameStack.Add(CurrentFrame.Next);
			switch (node.Bind)
			{
			case .Undefined:
				if (node.Body is CompoundStmt)
					CurrentFrame.Finalizers.Add(node.Body);
				else
					Runtime.NotImplemented();
			case .RootScope:
				if (node.Body is CompoundStmt)
					mFrameStack[0].Finalizers.Add(node.Body);
				else
					Runtime.NotImplemented();
			case .Mixin:
				Runtime.NotImplemented();
			case .Custom:
				Runtime.NotImplemented();
			}
			return .Continue;
		}

		public override VisitResult Visit(DeclarationStmt node)
		{
			for (let variable in node.Declaration.Variables)
			{
				if (!mVariables.TryAdd(variable.Name, node.Declaration.Specification))
					Debug.WriteLine($"Warning! Duplicate variable \"{variable.Name}\" ignored!");

				if (variable.Initializer != null)
					CurrentFrame.Statements.Add($"{variable.Name} = {variable.Initializer};");
			}
			return .Continue;
		}

		public override VisitResult Visit(ExpressionStmt node)
		{
			if (let callOpExpr = node.Expr as CallOpExpr)
			if (let mixinMemberExpr = callOpExpr.Expr as MixinMemberExpr)
			if (let identifier = mixinMemberExpr.Expr as IdentifierExpr)
			{
				if (identifier.Value == "YieldReturn")
				{
					if (!callOpExpr.Params.IsEmpty)
						CurrentFrame.ResultExpr = callOpExpr.Params[0];
					CurrentFrame.Exit = FrameExit.Suspend;
					CurrentFrame.Next = newFrame("block", $"yield.after [{mGroupCounter - 1}]");
					mFrameStack.Add(CurrentFrame.Next);
					return .Continue;
				}
				else if (identifier.Value == "YieldBreak")
				{
					for (let frame in mFrameStack.Reversed)
					{
						for (let statement in frame.Finalizers)
							CurrentFrame.Statements.Add(statement);
					}
					CurrentFrame.Exit = FrameExit.Return;
					CurrentFrame.ExitExpr = node.Expr;
					return .Continue;
				}
			}

			CurrentFrame.Statements.Add(node);
			return .Continue;
		}

		public override VisitResult Visit(ReturnStmt node)
		{
			Runtime.FatalError("Cannot return a value from an iterator. Use the YieldReturn mixin to return a value, or YieldBreak to end the iteration.");
		}

		public override VisitResult Visit(BreakStmt node)
		{
			Frame targetFrame = findFrame("exit_block");

			Runtime.Assert(targetFrame != null, "'break' is not applicable");

			for (let frame in mFrameStack.Reversed)
			{
				if (frame == targetFrame)
					break;
				for (let statement in frame.Finalizers)
					CurrentFrame.Statements.Add(statement);
			}

			CurrentFrame.Next = targetFrame;
			CurrentFrame.Exit = FrameExit.Jump;
			return .Continue;
		}

		public override VisitResult Visit(ContinueStmt node)
		{
			Frame targetFrame = findFrame("loop_inc");

			Runtime.Assert(targetFrame != null, "'continue' is not applicable");

			for (let frame in mFrameStack.Reversed)
			{
				if (frame == targetFrame)
					break;
				for (let statement in frame.Finalizers)
					CurrentFrame.Statements.Add(statement);
			}

			CurrentFrame.Next = targetFrame;
			CurrentFrame.Exit = FrameExit.Jump;
			return .Continue;
		}
	}
}

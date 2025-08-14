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
		private enum ScopeKind
		{
			Block,
			Loop
		}

		private class Scope
		{
			public ScopeKind Kind;
			public List<Statement> Finalizers = new .() ~ Release!(_);

			public this(ScopeKind kind)
			{
				Kind = kind;
			}
		}

		private Dictionary<StringView, TypeSpec> mVariables = new .() ~ Release!(_);
		private Dictionary<int, Frame> mFrames = new .() ~ Release!(_);
		private int mGroupCounter;
		private int mFrameCounter;
		private int mReservedFrameCounter;
		private List<Frame> mFrameStack = new .() ~ Release!(_);
		private List<Scope> mScopeStack = new .() ~ Release!(_);
		private List<String> mOwnedNames = new .() ~ Release!(_);

		private Frame CurrentFrame => !mFrameStack.IsEmpty ? mFrameStack.Back : null;
		private Scope CurrentScope => !mScopeStack.IsEmpty ? mScopeStack.Back : null;
		
		public Dictionary<StringView, TypeSpec> Variables => mVariables;
		public Dictionary<int, Frame> Frames => mFrames;

		public this()
		{
			mGroupCounter = 1;
			mFrameCounter = 0;
			mFrameStack.Add(newFrame(.Start));
			pushNewScope(.Block);
		}

		public void Clear()
		{
			mFrameStack.Clear();
			Release!(mVariables, DictionaryReleaseKind.Items);
			mVariables.Clear();
			Release!(mFrames, DictionaryReleaseKind.Items);
			mFrames.Clear();
			ReleaseItems!(mScopeStack);
			mScopeStack.Clear();

			mGroupCounter = 1;
			mFrameCounter = 0;
			mFrameStack.Add(newFrame(.Start));
			pushNewScope(.Block);
		}

		private String newOwnedName(String prefix, int gid)
		{
			String name = new .();
			name.AppendF("{0}{1}", prefix, gid);
			mOwnedNames.Add(name);
			return name;
		}

		private Frame newFrame(FrameKind kind)
		{
			Frame frame = new Frame(kind, null, mFrameCounter++);
			mFrames.Add(frame.Id, frame);
			return frame;
		}

		private Frame newFrame(FrameKind kind, String description, params Span<Object> args)
		{
			String desc = new .();
			if (args.IsEmpty)
				desc.Append(description);
			else
				desc.AppendF(description, params args);
			Frame frame = new Frame(kind, desc, mFrameCounter++);
			mFrames.Add(frame.Id, frame);
			return frame;
		}

		private Frame reserveFrame(FrameKind kind, String description, params Span<Object> args)
		{
			String desc = new .();
			if (args.IsEmpty)
				desc.Append(description);
			else
				desc.AppendF(description, params args);
			Frame frame = new Frame(kind, desc, -(++mReservedFrameCounter));
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

		private void deleteFrame(Frame frame)
		{
			defer delete frame;
			Runtime.Assert(mFrames.Remove(frame.Id));
		}

		private Frame findFrame(FrameKind kind)
		{
			for (let frame in mFrameStack.Reversed)
			{
				if (frame.Kind == kind)
					return frame;
			}
			return null;
		}

		private void popFrameStackUntil(Frame frame)
		{
			bool foundFrame = false;
			while (!mFrameStack.IsEmpty)
			{
				if (mFrameStack.Back == frame)
				{
					foundFrame = true;
					break;
				}
				mFrameStack.PopBack();
			}
			Runtime.Assert(foundFrame, "Frame stack corruption detected.");
		}

		private Scope pushNewScope(ScopeKind kind)
		{
			return mScopeStack.Add(.. new Scope(kind));
		}

		private void popCurrentScope(bool emitScopeFinalizers = false)
		{
			Runtime.Assert(!mScopeStack.IsEmpty);
			let curScope = mScopeStack.PopBack();
			if (emitScopeFinalizers)
			{
				for (int i = curScope.Finalizers.Count - 1; i >= 0; i--)
					CurrentFrame.Statements.Add(curScope.Finalizers[i]);
			}
		}

		private Scope findScope(ScopeKind kind)
		{
			for (let theScope in mScopeStack.Reversed)
			{
				if (theScope.Kind == kind)
					return theScope;
			}
			return null;
		}

		private void emitAllFinalizers(ScopeKind? stopScope = null)
		{
			bool foundScope = !stopScope.HasValue;
			for (int i = mScopeStack.Count - 1; i >= 0; i--)
			{
				let theScope = mScopeStack[i];
				if (theScope.Kind == stopScope)
				{
					foundScope = true;
					break;
				}

				for (int j = theScope.Finalizers.Count - 1; j >= 0; j--)
					CurrentFrame.Statements.Add(theScope.Finalizers[j]);
			}
			Runtime.Assert(foundScope, "Scope stack corruption detected.");
		}

		/// This will discard the VisitResult!
		public new void Visit(ASTNode node)
		{
			node.Accept(this);
		}

		public override VisitResult Visit(CompoundStmt compStmt)
		{
			pushNewScope(.Block);

			for (let ast in compStmt.Statements)
			{
				Visit(ast);
				if (CurrentFrame.Exit == .Return)
				{
					// Finalizers were already emitted at the point of YieldBreak!
					popCurrentScope();
					return .Continue;
				}
			}

			popCurrentScope(true);
			return .Continue;
		}

		public override VisitResult Visit(DoStmt node)
		{
			Runtime.NotImplemented();
		}

		public override VisitResult Visit(UsingStmt node)
		{
			int gid = mGroupCounter++;
		    Frame initialFrame = CurrentFrame;
		    int index = initialFrame.Statements.Count;

			List<StringView> varNames = scope .();
			if (node.Decl != null)
			{
				for (let variable in node.Decl.Variables)
				{
					if (!mVariables.TryAdd(variable.Name, node.Decl.Specification))
						Debug.WriteLine($"Warning! Duplicate variable \"{variable.Name}\" ignored!");

					if (variable.Initializer != null)
						CurrentFrame.Statements.Add($"{variable.Name} = {variable.Initializer};");

					varNames.Add(variable.Name);
				}
			}
			else
			{
				let tmpName = newOwnedName("__using_", gid);
				if (!mVariables.ContainsKey(tmpName))
				{
					mVariables.Add(tmpName, new ExprModTypeSpec() { Type = .DeclType, Expr = node.Expr });
				}
				else
				{
					Debug.WriteLine($"Warning! Duplicate temp var \"{tmpName}\" ignored!");
				}
				CurrentFrame.Statements.Add($"{tmpName} = {node.Expr};");
				varNames.Add(tmpName);
			}

			pushNewScope(.Block);

			for (let variable in varNames)
			{
				CurrentScope.Finalizers.Add($"{variable}.Dispose();");
			}

			Visit(node.Body);

			if (CurrentFrame != initialFrame || CurrentFrame.Exit != .Continue)
			{
			    popCurrentScope(CurrentFrame.Exit != .Return);
			}
			else
			{
				// (OPTIMIZATION)
				// This means the flow of this statement is straightforward (flat),
				// so the statement can be directly appended to the current frame.
				popFrameStackUntil(initialFrame);

				for (let variable in varNames.Reversed)
				{
				    if (!variable.IsEmpty)
				        mVariables.Remove(variable);
				}

				var nodeCount = initialFrame.Statements.Count - index;
				if (nodeCount > 0)
				    initialFrame.Statements.RemoveRange(index, nodeCount);
				initialFrame.Statements.Add(node);

				popCurrentScope();
			}

			return .Continue;
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
					elseFrame = newFrame(.Block, $"if.else [{gid}]");
					mFrameStack.Add(elseFrame);
					Visit(node.ElseStatement);
					elseFrameTail = CurrentFrame;
					popFrameStackUntil(thenFrame);
				}

				Frame afterFrame = newFrame(.Block, $"if.out [{gid}]");
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

				popFrameStackUntil(initialFrame);

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

					Frame afterFrame = newFrame(.Block, $"if.out [{gid}]");

					// We already know the control-flow of the ThenStatement is flat, so it's okay to add it directly here.
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

			Frame afterFrame = reserveFrame(.ExitBlock, $"for.out [{gid}]");
			mFrameStack.Add(afterFrame);

			Frame incFrame = reserveFrame(.LoopIncrement, $"for.inc [{gid}]");
			mFrameStack.Add(incFrame);

			Frame bodyFrame = newFrame(.Block, $"for.body [{gid}]");
			mFrameStack.Add(bodyFrame);

			List<StringView> varDecls = scope .();
			if (node.Declaration != null)
			{
				for (let variable in node.Declaration.Variables)
				{
					if (!mVariables.ContainsKey(variable.Name))
					{
						mVariables.Add(variable.Name, node.Declaration.Specification);
						varDecls.Add(variable.Name);
					}
					else
					{
						Debug.WriteLine($"Warning! Duplicate var \"{variable.Name}\" ignored!");
						varDecls.Add("");
					}

					initialFrame.Statements.Add($"{variable.Name} = {variable.Initializer};");
				}
			}

			let loopScope = pushNewScope(.Loop);
			defer popCurrentScope();
			
			Visit(node.Body);

			if (bodyFrame != CurrentFrame || CurrentFrame.Exit != .Continue)
			{
				Frame bodyFrameTail = CurrentFrame;

				// The initialFrame should jump to the loop frame.
				initialFrame.Next = bodyFrame;

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

				Runtime.Assert(loopScope == CurrentScope);
				for (int j = loopScope.Finalizers.Count - 1; j >= 0; j--)
					afterFrame.Statements.Insert(0, loopScope.Finalizers[j]);

				popFrameStackUntil(afterFrame);
			}
			else
			{
				// (OPTIMIZATION)
				// This means the flow of this statement is straightforward (flat),
				// so the statement can be directly appended to the current frame without needing additional frames.
				deleteFrame(bodyFrame);
				popFrameStackUntil(initialFrame);

				for (var variable in varDecls)
				{
					if (!variable.IsEmpty)
						mVariables.Remove(variable);
					initialFrame.Statements.PopBack();
				}

				initialFrame.Statements.Add(node);
			}

			return .Continue;
		}

		public override VisitResult Visit(ForeachStmt node)
		{
			int gid = mGroupCounter++;
			Frame initialFrame = CurrentFrame;
			
			Frame afterFrame = reserveFrame(.ExitBlock, $"foreach.out [{gid}]");
			mFrameStack.Add(afterFrame);

			Frame incFrame = reserveFrame(.LoopIncrement, $"foreach.inc [{gid}]");
			mFrameStack.Add(incFrame);

			Frame bodyFrame = newFrame(.Block, $"foreach.body [{gid}]");
			mFrameStack.Add(bodyFrame);
			
			List<StringView> varDecls = scope .();

			let tempName = newOwnedName("__enumerator_", CurrentFrame.Id);
			if (!mVariables.ContainsKey(tempName))
			{
				mVariables.Add(tempName, new ExprModTypeSpec() { Type = .DeclType, Expr = new CallOpExpr() { Expr = new IdentifierExpr() { Value = "__GetEnumerator" }, Params = new List<Expression>() { node.SourceExpr } } }); // decltype(__GetEnumerator({sourceExpr}))
				varDecls.Add(tempName);
			}
			else
			{
				Debug.WriteLine($"Warning! Duplicate var \"{tempName}\" ignored!");
				varDecls.Add("");
			}

			initialFrame.Statements.Add($"{tempName} = __GetEnumerator({node.SourceExpr});");

			if (!mVariables.ContainsKey(node.TargetName))
			{
				let genericName = new GenericName() { Identifier = "Result" };
				genericName.TypeArguments.Add(node.TargetType);
				mVariables.Add(node.TargetName, genericName);
				varDecls.Add(node.TargetName);
			}
			else
			{
				Debug.WriteLine($"Warning! Duplicate var \"{node.TargetName}\" ignored!");
				varDecls.Add("");
			}

			initialFrame.Statements.Add($"{node.TargetName} = {tempName}.GetNext();");

			let loopScope = pushNewScope(.Loop);
			defer popCurrentScope();

			CurrentScope.Finalizers.Add(
				$$"""
				if (CheckTypeNoWarn!<System.IDisposable>({{tempName}})) [ConstSkip]
				{
					{{tempName}}.Dispose();
				}
				""");
			
			Visit(node.Body);

			if (bodyFrame != CurrentFrame || CurrentFrame.Exit != .Continue)
			{
				Frame bodyFrameTail = CurrentFrame;

				// The initialFrame should jump to the loop frame.
				initialFrame.Next = bodyFrame;

				addReservedFrame(incFrame);
				incFrame.Statements.Add($"{node.TargetName} = {tempName}.GetNext();");
				
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

				Runtime.Assert(loopScope == CurrentScope);
				for (int j = loopScope.Finalizers.Count - 1; j >= 0; j--)
					afterFrame.Statements.Insert(0, loopScope.Finalizers[j]);

				popFrameStackUntil(afterFrame);
			}
			else
			{
				// (OPTIMIZATION)
				// This means the flow of this statement is straightforward (flat),
				// so the statement can be directly appended to the current frame without needing additional frames.
				deleteFrame(bodyFrame);
				popFrameStackUntil(initialFrame);

				for (var variable in varDecls)
				{
					if (!variable.IsEmpty)
						mVariables.Remove(variable);
					initialFrame.Statements.PopBack();
				}

				initialFrame.Statements.Add(node);
			}

			return .Continue;
		}

		public override VisitResult Visit(WhileStmt node)
		{
			int gid = mGroupCounter++;
			Frame initialFrame = CurrentFrame;
			
			Frame afterFrame = reserveFrame(.ExitBlock, $"while.out [{gid}]");
			mFrameStack.Add(afterFrame);

			Frame bodyFrame = newFrame(.Block, $"while.body [{gid}]");
			mFrameStack.Add(bodyFrame);

			let loopScope = pushNewScope(.Loop);
			defer popCurrentScope();
			
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

				Runtime.Assert(loopScope == CurrentScope);
				for (int j = loopScope.Finalizers.Count - 1; j >= 0; j--)
					afterFrame.Statements.Insert(0, loopScope.Finalizers[j]);

				popFrameStackUntil(afterFrame);
			}
			else
			{
				// (OPTIMIZATION)
				// This means the flow of this statement is straightforward (flat),
				// so the statement can be directly appended to the current frame without needing additional frames.
				deleteFrame(bodyFrame);
				popFrameStackUntil(initialFrame);

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
			switch (node.Bind)
			{
			case .Undefined:
				// TODO: Expressions that are deferred must capture the used values.
				Runtime.Assert(!(node.Body is ExpressionStmt), "Expression defer not implemented!");

				CurrentScope.Finalizers.Add(node.Body);
			case .RootScope:
				// TODO: Expressions that are deferred must capture the used values.
				Runtime.Assert(!(node.Body is ExpressionStmt), "Expression defer not implemented!");

				Runtime.Assert(!mScopeStack.IsEmpty);
				mScopeStack[0].Finalizers.Add(node.Body);
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
					CurrentFrame.Next = newFrame(.Block, $"yield.after [{mGroupCounter - 1}]");
					mFrameStack.Add(CurrentFrame.Next);
					return .Continue;
				}
				else if (identifier.Value == "YieldBreak")
				{
					emitAllFinalizers();
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
			Frame targetFrame = findFrame(.ExitBlock);
			Runtime.Assert(targetFrame != null, "'break' is not applicable");

			// Only inner block defers. Loop finalizers are in the exit frame.
			emitAllFinalizers(.Loop);

			CurrentFrame.Next = targetFrame;
			CurrentFrame.Exit = FrameExit.Jump;
			return .Continue;
		}

		public override VisitResult Visit(ContinueStmt node)
		{
			Frame targetFrame = findFrame(.LoopIncrement);
			Runtime.Assert(targetFrame != null, "'continue' is not applicable");
			
			// Only inner block defers. Loop finalizers are in the exit frame.
			emitAllFinalizers(.Loop);

			CurrentFrame.Next = targetFrame;
			CurrentFrame.Exit = FrameExit.Jump;
			return .Continue;
		}
	}
}

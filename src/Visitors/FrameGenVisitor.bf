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
		protected enum ScopeKind
		{
			Block	= 1 << 0,
			Loop	= 1 << 1,
			Switch	= 1 << 2
		}

		protected class Scope
		{
			public ScopeKind Kind;
			public List<Statement> Finalizers = new .() ~ Release!(_);
			public Frame BreakTarget;
			public Frame ContinueTarget;

			public this(ScopeKind kind)
			{
				Kind = kind;
			}
		}

		protected struct LabelInfo
		{
			public Frame BreakTarget;
			public Frame ContinueTarget;
		}

		protected Dictionary<StringView, TypeSpec> mVariables = new .() ~ Release!(_);
		protected Dictionary<int, Frame> mFrames = new .() ~ Release!(_);
		protected int mGroupCounter;
		protected int mFrameCounter;
		private int mReservedFrameCounter;
		protected List<Frame> mFrameStack = new .() ~ Release!(_);
		protected List<Scope> mScopeStack = new .() ~ Release!(_);
		private List<String> mOwnedNames = new .() ~ Release!(_);

		protected Dictionary<StringView, LabelInfo> mLabels = new .() ~ Release!(_);
		private StringView mPendingLabel;

		protected Frame CurrentFrame => !mFrameStack.IsEmpty ? mFrameStack.Back : null;
		protected Scope CurrentScope => !mScopeStack.IsEmpty ? mScopeStack.Back : null;
		
		public Dictionary<StringView, TypeSpec> Variables => mVariables;
		public Dictionary<int, Frame> Frames => mFrames;

		public this()
		{
			mGroupCounter = 1;
			mFrameCounter = 0;
			mFrameStack.Add(newFrame("start"));
			pushNewScope(.Block);
		}

		public void Clear()
		{
			mFrameStack.Clear();
			Release!(mVariables, DictionaryReleaseKind.Items);
			mVariables.Clear();
			Release!(mFrames, DictionaryReleaseKind.Items);
			mFrames.Clear();
			Release!(mScopeStack, ContainerReleaseKind.Items);
			mScopeStack.Clear();
			Release!(mLabels, DictionaryReleaseKind.Items);
			mLabels.Clear();

			mGroupCounter = 1;
			mFrameCounter = 0;
			mFrameStack.Add(newFrame("start"));
			pushNewScope(.Block);
		}

		protected String newOwnedName(String prefix, int gid)
		{
			String name = new .();
			name.AppendF("{0}{1}", prefix, gid);
			mOwnedNames.Add(name);
			return name;
		}

		protected Frame newFrame(String description)
		{
			String desc = new .();
			desc.Append(description);
			Frame frame = new Frame(desc, mFrameCounter++);
			mFrames.Add(frame.Id, frame);
			return frame;
		}

		protected Frame newFrame(String description, params Span<Object> args)
		{
			String desc = new .();
			if (args.IsEmpty)
				desc.Append(description);
			else
				desc.AppendF(description, params args);
			Frame frame = new Frame(desc, mFrameCounter++);
			mFrames.Add(frame.Id, frame);
			return frame;
		}

		protected Frame reserveFrame(String description, params Span<Object> args)
		{
			String desc = new .();
			if (args.IsEmpty)
				desc.Append(description);
			else
				desc.AppendF(description, params args);
			Frame frame = new Frame(desc, -(++mReservedFrameCounter));
			mFrames.Add(frame.Id, frame);
			return frame;
		}

		protected void addReservedFrame(Frame frame)
		{
			Runtime.Assert(frame.Id < 0);
			Runtime.Assert(mFrames.Remove(frame.Id));
			frame.[Friend]Id = mFrameCounter++;
			mFrames.Add(frame.Id, frame);
		}

		protected void deleteFrame(Frame frame)
		{
			defer delete frame;
			Runtime.Assert(mFrames.Remove(frame.Id));
		}

		protected void popFrameStackUntil(Frame frame)
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

		protected Scope pushNewScope(ScopeKind kind)
		{
			return mScopeStack.Add(.. new Scope(kind));
		}

		protected void popCurrentScope(bool emitScopeFinalizers = false)
		{
			Runtime.Assert(!mScopeStack.IsEmpty);
			let curScope = mScopeStack.PopBack();
			if (emitScopeFinalizers)
			{
				for (int i = curScope.Finalizers.Count - 1; i >= 0; i--)
					CurrentFrame.Statements.Add(curScope.Finalizers[i]);
			}
		}

		protected Scope findScope(ScopeKind kind)
		{
			for (let theScope in mScopeStack.Reversed)
			{
				if (kind.HasFlag(theScope.Kind))
					return theScope;
			}
			return null;
		}

		protected void emitAllFinalizers(ScopeKind? stopScope = null)
		{
			bool foundScope = !stopScope.HasValue;
			for (int i = mScopeStack.Count - 1; i >= 0; i--)
			{
				let theScope = mScopeStack[i];
				if (stopScope?.HasFlag(theScope.Kind) == true)
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

			VarBindingCollector varBindingCollector = scope .();
			varBindingCollector.Visit(node.Condition);
			
			List<StringView> varDecls = scope .();
			if (!varBindingCollector.Results.IsEmpty)
			{
				for (let variable in varBindingCollector.Results)
				{
					if (!mVariables.ContainsKey(variable.Name))
					{
						mVariables.Add(variable.Name, variable.Type);
						varDecls.Add(variable.Name);
					}
					else
					{
						Debug.WriteLine($"Warning! Duplicate var \"{variable.Name}\" ignored!");
						varDecls.Add("");
					}
				}
			}

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
					elseFrame = newFrame($"if.else [{gid}]");
					mFrameStack.Add(elseFrame);
					Visit(node.ElseStatement);
					elseFrameTail = CurrentFrame;
					popFrameStackUntil(thenFrame);
				}

				// Rewrite the inline variable declarations as 'out'.
				node.Condition = VarBindingLowerer.Rewrite(node.Condition);

				Frame afterFrame = newFrame($"if.out [{gid}]");
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

			for (var variable in varDecls)
			{
				if (!variable.IsEmpty)
					mVariables.Remove(variable);
			}
			varDecls.Clear();

			if (node.ElseStatement != null)
			{
				index = initialFrame.Statements.Count;

				Visit(node.ElseStatement);

				if (CurrentFrame != initialFrame || CurrentFrame.Exit != .Continue)
				{
					Frame elseFrame = CurrentFrame;

					Frame afterFrame = newFrame($"if.out [{gid}]");

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
					if (elseFrame.Exit == .Continue)
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
			int gid = mGroupCounter++;
			Frame initialFrame = CurrentFrame;

			StringView stmtLabel = mPendingLabel;
			mPendingLabel = default;

			if (node.Sections.IsEmpty)
			{
				if (node.DefaultSection != null)
				{
					Statement body = (node.DefaultSection.Statements.Count == 1)
						? node.DefaultSection.Statements[0]
						: scope CompoundStmt() { Statements = new List<Statement>(node.DefaultSection.Statements) };
					Visit(body);
				}
				return .Continue;
			}

			// This is the 'after-switch' frame that 'break' will jump to.
			Frame afterFrame = reserveFrame($"switch.out [{gid}]");
			mFrameStack.Add(afterFrame);

			if (!stmtLabel.IsNull)
				mLabels.Add(stmtLabel, .() { BreakTarget = afterFrame, ContinueTarget = null });

			// Temporarily push the initial frame back on top so we continue building on it.
			mFrameStack.Add(initialFrame);

			let switchScope = pushNewScope(.Switch);
			switchScope.BreakTarget = afterFrame;
			switchScope.ContinueTarget = null;
			defer popCurrentScope();

			String tmpName = newOwnedName("__switchVal_", gid);
			if (!mVariables.ContainsKey(tmpName))
			{
				mVariables.Add(tmpName, new ExprModTypeSpec() { Type = .DeclType, Expr = node.Expr });
			}
			else
			{
				Debug.WriteLine($"Warning! Duplicate temp var \"{tmpName}\" ignored!");
			}
			CurrentFrame.Statements.Add($"{tmpName} = {node.Expr};");

			IfStmt rootIf = null;
			IfStmt currentIf = null;

			// Build an if/else-if chain from the switch sections.
			for (var section in node.Sections)
			{
				Expression condition = null;
				for (var label in section.Labels)
				{
					Expression test;
					if (label is Literal || label is IdentifierExpr)
						test = new BinaryOpExpr() { Left = new IdentifierExpr(tmpName), Operation = .Equal, Right = label };
					else
						test = new ComparisonOpExpr() { Type = .Case, Left = new IdentifierExpr(tmpName), Right = label };

					condition = (condition == null)
								 ? test
								 : new BinaryOpExpr() { Left = condition, Operation = .Or, Right = test };
				}

				if (section.WhenExpr != null)
					condition = new BinaryOpExpr() { Left = condition, Operation = .And, Right = section.WhenExpr };

				Statement body = (section.Statements.Count == 1)
						? section.Statements[0]
						: new CompoundStmt() { Statements = new List<Statement>(section.Statements) };

				var newIf = new IfStmt() { Condition = condition, ThenStatement = body };

				if (rootIf == null)
					rootIf = newIf;
				else
					currentIf.ElseStatement = newIf;

				currentIf = newIf;
			}

			// The 'default' section becomes the final 'else' block.
			if (node.DefaultSection != null)
			{
				Statement body = (node.DefaultSection.Statements.Count == 1)
					? node.DefaultSection.Statements[0]
					: new CompoundStmt() { Statements = new List<Statement>(node.DefaultSection.Statements) };
				Runtime.Assert(currentIf != null);
				currentIf.ElseStatement = body;
			}

			Visit(rootIf);

			Frame lastBranchTail = CurrentFrame;
			if (lastBranchTail.Exit == .Continue)
				lastBranchTail.Next = afterFrame;

			addReservedFrame(afterFrame);

			Runtime.Assert(switchScope == CurrentScope);
			for (int j = switchScope.Finalizers.Count - 1; j >= 0; j--)
				afterFrame.Statements.Insert(0, switchScope.Finalizers[j]);

			popFrameStackUntil(afterFrame);
			return .Continue;
		}

		public override VisitResult Visit(ForStmt node)
		{
			int gid = mGroupCounter++;
			Frame initialFrame = CurrentFrame;

			Frame afterFrame = reserveFrame($"for.out [{gid}]");
			mFrameStack.Add(afterFrame);

			Frame incFrame = reserveFrame($"for.inc [{gid}]");
			mFrameStack.Add(incFrame);

			Frame bodyFrame = newFrame($"for.body [{gid}]");
			mFrameStack.Add(bodyFrame);

			if (!mPendingLabel.IsNull)
			{
				mLabels.Add(mPendingLabel, .() { BreakTarget = afterFrame, ContinueTarget = incFrame });
				mPendingLabel = default;
			}

			List<(StringView, bool)> varDecls = scope .();
			if (node.Declaration != null)
			{
				for (let variable in node.Declaration.Variables)
				{
					if (!mVariables.ContainsKey(variable.Name))
					{
						mVariables.Add(variable.Name, node.Declaration.Specification);
						varDecls.Add((variable.Name, variable.Initializer != null));
					}
					else
					{
						Debug.WriteLine($"Warning! Duplicate var \"{variable.Name}\" ignored!");
						varDecls.Add(("", variable.Initializer != null));
					}

					if (variable.Initializer != null)
						initialFrame.Statements.Add($"{variable.Name} = {variable.Initializer};");
				}
			}

			let loopScope = pushNewScope(.Loop);
			loopScope.BreakTarget = afterFrame;
			loopScope.ContinueTarget = incFrame;
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

				for (let (variable, hasInitializer) in varDecls)
				{
					if (!variable.IsEmpty)
						mVariables.Remove(variable);
					if (hasInitializer)
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
			loopScope.BreakTarget = afterFrame;
			loopScope.ContinueTarget = incFrame;
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
			
			Frame afterFrame = reserveFrame($"while.out [{gid}]");
			mFrameStack.Add(afterFrame);

			Frame bodyFrame = newFrame($"while.body [{gid}]");
			mFrameStack.Add(bodyFrame);
		    
			if (!mPendingLabel.IsNull)
			{
				mLabels.Add(mPendingLabel, .() { BreakTarget = afterFrame, ContinueTarget = bodyFrame });
				mPendingLabel = default;
			}

			let loopScope = pushNewScope(.Loop);
			loopScope.BreakTarget = afterFrame;
			loopScope.ContinueTarget = bodyFrame;
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
					CurrentFrame.Next = newFrame($"yield.after [{mGroupCounter - 1}]");
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
			Frame targetFrame;
			if (!node.TargetLabel.IsNull)
			{
				if (!mLabels.TryGetValue(node.TargetLabel, let labelInfo))
					Runtime.FatalError(scope $"Label '{node.TargetLabel}' not found for 'break' statement");
				targetFrame = labelInfo.BreakTarget;
				Runtime.Assert(targetFrame != null, scope $"'break' is not applicable to the statement with label '{node.TargetLabel}'");
			}
			else
			{
				targetFrame = findScope(.Loop | .Switch)?.BreakTarget;
				Runtime.Assert(targetFrame != null, "'break' is not applicable");
			}

			// Only inner block defers. Loop finalizers are in the exit frame.
			emitAllFinalizers(.Loop | .Switch);

			CurrentFrame.Next = targetFrame;
			CurrentFrame.Exit = FrameExit.Jump;
			return .Continue;
		}

		public override VisitResult Visit(ContinueStmt node)
		{
			Frame targetFrame;
			if (!node.TargetLabel.IsNull)
			{
				if (!mLabels.TryGetValue(node.TargetLabel, let labelInfo))
					Runtime.FatalError(scope $"Label '{node.TargetLabel}' not found for continue statement");
				targetFrame = labelInfo.ContinueTarget;
				Runtime.Assert(targetFrame != null, scope $"'continue' is not applicable to the statement with label '{node.TargetLabel}'");
			}
			else
			{
				targetFrame = findScope(.Loop)?.ContinueTarget;
				Runtime.Assert(targetFrame != null, "'continue' is not applicable");
			}
			
			// Only inner block defers. Loop finalizers are in the exit frame.
			emitAllFinalizers(.Loop);

			CurrentFrame.Next = targetFrame;
			CurrentFrame.Exit = FrameExit.Jump;
			return .Continue;
		}

		public override VisitResult Visit(FallthroughStmt node)
		{
			Runtime.NotImplemented();
		}

		public override VisitResult Visit(LabeledStmt node)
		{
			if (mLabels.ContainsKey(node.Label))
			{
				Debug.WriteLine($"Warning! Duplicate label '{node.Label}'");
				return .Continue;
			}

			mPendingLabel = node.Label;
			defer mLabels.Remove(node.Label);

			Visit(node.Statement);

			if (mPendingLabel != default)
			{
				mPendingLabel = default;
				Runtime.FatalError(scope $"Label '{node.Label}' is not attached to an labelable statement.");
			}

			return .Continue;
		}
	}
}

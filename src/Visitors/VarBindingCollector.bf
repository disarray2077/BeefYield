using System;
using System.Collections;
using BeefParser;
using BeefParser.AST;

namespace BeefYield
{
	/// Scans an AST expression to find 'let' and 'var' variable bindings
	public class VarBindingCollector : ASTWalker
	{
		public struct FoundVar
		{
			public StringView Name;
			public TypeSpec Type;
		}

		private List<FoundVar> mFound = new .() ~ Release!(_);

		private struct CaseContext
		{
			public Expression Lhs;
			public Expression Rhs;
		}
		private List<CaseContext> mCaseStack = new .() ~ Release!(_);

		public Span<FoundVar> Results => mFound;

		public void Reset()
		{
			Release!(mFound, ContainerReleaseKind.Items);
			mFound.Clear();
			mCaseStack.Clear();
		}

		public override VisitResult Visit(LetExpr letExpr)
		{
			RecordLetOrVar(letExpr.Expr);
			return base.Visit(letExpr);
		}

		public override VisitResult Visit(VarExpr varExpr)
		{
			RecordLetOrVar(varExpr.Expr);
			return base.Visit(varExpr);
		}

		public override VisitResult Visit(ComparisonOpExpr compOpExpr)
		{
			if (compOpExpr.Type == .Case)
			{
				Visit(compOpExpr.Left);

				mCaseStack.Add(.() { Lhs = compOpExpr.Left, Rhs = compOpExpr.Right });
				Visit(compOpExpr.Right);
				mCaseStack.PopBack();

				return .Continue;
			}

			return base.Visit(compOpExpr);
		}

		private void RecordLetOrVar(Expression nameExpr)
		{
			IdentifierExpr ident = nameExpr as IdentifierExpr;
			if (ident == null)
				return;

			let name = ident.Value;

			for (let fv in mFound)
				if (fv.Name == name)
					return;

			let typeSpec = InferTypeFromContext(name);
			mFound.Add(.() { Name = name, Type = typeSpec });
		}

		private TypeSpec InferTypeFromContext(StringView name)
		{
			if (!mCaseStack.IsEmpty)
			{
				let ctx = mCaseStack.Back;
				String witness = scope $$"{ let _ = {{ctx.Lhs}} case {{ctx.Rhs}}; _ = ?; {{name}} }";
				return new ExprModTypeSpec()
				{
					Type = .DeclType,
					Expr = BeefParser.ParseTo(witness, .. ?)
				};
			}
			return null;
		}
	}
}
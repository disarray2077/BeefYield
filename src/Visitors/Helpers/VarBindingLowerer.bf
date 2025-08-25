using System;
using BeefParser;
using BeefParser.AST;

namespace BeefYield
{
	/// Rewrites an AST expression, transforming 'LetExpr' nodes into 'OutExpr' nodes.
	public class VarBindingLowerer : ASTRewriter
	{
		public static Expression Rewrite(Expression expr)
		{
			let lowerer = scope VarBindingLowerer();
			return (Expression)lowerer.Visit(expr);
		}

		public override ASTNode Visit(LetExpr letExpr)
		{
			var outExpr = new OutExpr()
			{
				Expr = letExpr.Expr
			};
			letExpr.Expr = null;
			delete letExpr;
			return outExpr;
		}

		public override ASTNode Visit(IfStmt ifStmt)
		{
			ifStmt.Condition = (Expression)Visit(ifStmt.Condition);
			return ifStmt;
		}

		public override ASTNode Visit(WhileStmt whileStmt)
		{
			whileStmt.Condition = (Expression)Visit(whileStmt.Condition);
			return whileStmt;
		}

		public override ASTNode Visit(ForStmt forStmt)
		{
			forStmt.Condition = (Expression)Visit(forStmt.Condition);
			VisitList(forStmt.Incrementors);
			return forStmt;
		}

		public override ASTNode Visit(SwitchStmt switchStmt)
		{
			switchStmt.Expr = (Expression)Visit(switchStmt.Expr);
			return switchStmt;
		}

		public override ASTNode Visit(UsingStmt usingStmt)
		{
			if (usingStmt.Expr != null)
			{
				usingStmt.Expr = (Expression)Visit(usingStmt.Expr);
			}
			return usingStmt;
		}
	}
}
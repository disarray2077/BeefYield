using System;
using System.Collections;
using BeefParser.AST;

namespace BeefYield
{
	enum FrameKind
	{
		Start,
		Block,
		ExitBlock,
		LoopIncrement,
	}

	enum FrameExit
	{
		Continue,
		Suspend,
		Jump,
		Return
	}

	class Frame
	{
		public FrameKind Kind { get; private set; }
		public String Description { get; private set; } ~ delete _;
		public int Id { get; private set; }
		public readonly List<Statement> Statements = new .() ~ delete _;
		public FrameExit Exit = .Continue;
		public Expression ExitExpr;
		public Expression ResultExpr;

		private Frame mNext;
		public Frame Next
		{
			get => mNext;
			set
			{
				Runtime.Assert(mNext == null, "Attempt to overwrite an existing frame transition!");
				if (value.Id == -1)
					System.Diagnostics.Debug.Break();
				mNext = value;
			}
		}

		public this(FrameKind kind, String description, int id)
		{
			Kind = kind;
			Description = description;
			Id = id;
		}
	}
}
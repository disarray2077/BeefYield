using System;
using System.Collections;
using BeefParser.AST;

namespace BeefYield
{
	enum FrameExit
	{
		Continue,
		Suspend,
		Jump,
		Return
	}

	class Frame
	{
		public String Name { get; private set; }
		public String Description { get; private set; } ~ delete _;
		public int Id { get; private set; }
		public readonly List<Statement> Statements = new .() ~ delete _;
		public readonly List<Statement> Finalizers = new .() ~ delete _;
		public FrameExit Exit = .Continue;
		public Expression ExitExpr;
		public Expression ResultExpr;

		private Frame mNext;
		public Frame Next
		{
			get => mNext;
			set
			{
				Runtime.Assert(mNext == null);
				if (value.Id == -1)
					System.Diagnostics.Debug.Break();
				mNext = value;
			}
		}

		public this(String name, String description, int id)
		{
			Name = name;
			Description = description;
			Id = id;
		}
	}
}
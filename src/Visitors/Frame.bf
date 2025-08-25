using System;
using System.Collections;
using BeefParser.AST;
using System.Diagnostics;

namespace BeefYield
{
	enum FrameExit
	{
		/// this frame continues to the next frame
		Continue,
		/// this frame must suspend the iteration and yield to the caller
		Suspend,
		/// this frame must jump to another frame
		Jump,
		/// this frame must abort the iteration and return to the caller
		Return
	}

	class Frame
	{
		public String Description { get; private set; } ~ delete _;
		public int Id { get; private set; }
		public readonly List<Statement> Statements = new .() ~ delete _;
		public FrameExit Exit = .Continue;
		public Expression ExitExpr;
		public Expression ResultExpr;

		public readonly List<Frame> InlinedTargets = new .() ~ delete _;

		private Frame mNext;
		public Frame Next
		{
			get => mNext;
			set
			{
				if (mNext != null && mNext != value)
					Debug.Break();

				// If this assert fails, it usually means the current frame should have ended 
				// and we should already be processing the next one, but for some reason we're 
				// still stuck in the previous frame.
				Runtime.Assert(mNext == null || mNext == value, "Attempt to overwrite an existing frame transition!");

				//if (value?.Id == -1)
				//	Debug.Break();

				mNext = value;
			}
		}

		public this(String description, int id)
		{
			Description = description;
			Id = id;
		}

		public void RegisterInlineJump(Frame to)
		{
			if (to == null)
			    return;
			InlinedTargets.Add(to);
		}
	}
}
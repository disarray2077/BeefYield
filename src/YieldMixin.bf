using System;

namespace BeefYield;

static
{
	[NoReturn]
	public static mixin YieldBreak()
	{
		Runtime.FatalError(); // nothing
	}

	[NoReturn]
	public static mixin YieldReturn()
	{
		Runtime.FatalError(); // nothing
	}

	[NoReturn]
	public static mixin YieldReturn(var value)
	{
		Runtime.FatalError(); // nothing
	}
}
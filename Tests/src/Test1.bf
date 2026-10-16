using System;
using BeefYield;
using System.Diagnostics;

namespace BeefYield.Tests
{
	class Test1
	{
		[MakeYieldable]
		public static YieldEnumerator<int> Yieldable(int n)
		{
#unwarn
			if (n <= 1)
				YieldReturn!(n);
	
			int t1 = 0, t2 = 1, nextTerm = t1 + t2;
			while (nextTerm <= n)
			{
				YieldReturn!(nextTerm);
				t1 = t2;
				t2 = nextTerm;
				nextTerm = t1 + t2;
			}
		}
	
		[Test]
		public static void Test1()
		{
			int final = 0;
			for (let i in Yieldable(100))
			{
				Debug.WriteLine("Fib: {}", i);
				final = i;
			}

			Test.Assert(final == 89);
			GC.Collect(false);
		}
	}
}

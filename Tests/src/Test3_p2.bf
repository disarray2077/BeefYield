using System;
using BeefYield;
using System.Diagnostics;
using System.Collections;

namespace BeefYield.Tests
{
	class Test3_P2
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\Test3_P2.bf";

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<char8> Yieldable(List<char8> str)
		{
#unwarn
			Debug.WriteLine("Start");
			
			for (int j = 0; j < 2; j++)
			{
				for (char8 res in Yieldable2(str, (c) => c != '.'))
				{
					YieldReturn!(res);
				}
			}

			Debug.WriteLine("End");
		}

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<T> Yieldable2<T, TEnum, TPred>(TEnum enumerator, TPred predicate)
			where TEnum : concrete, IEnumerable<T>
			where TPred : delegate bool(T a)
		{
#unwarn
			for (T res in enumerator)
			{
				if (predicate(res))
					YieldReturn!(res);
			}

			YieldBreak!();
		}
	
		[Test]
		public static void Test3_P2()
		{
			List<char8> beef = scope .(){ 'B', '.', 'e', '.', 'e', '.', 'f' };

			int count = 0;
			for (let i in Yieldable(beef))
			{
				Debug.WriteLine("Char: {}", i);
				count++;
			}

			Test.Assert(count == 8);
			GC.Collect(false);
		}
	}
}
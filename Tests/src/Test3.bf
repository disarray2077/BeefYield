using System;
using BeefYield;
using System.Diagnostics;
using System.Collections;

namespace BeefYield.Tests
{
	class Test3
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\Test3.bf";

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<char8> Yieldable(String str)
		{
#unwarn
			Debug.WriteLine("Start");
			
			for (int j = 0; j < 2; j++)
			{
				for (char8 res in Yieldable2(str.RawChars, (c) => c != '.'))
				{
					YieldReturn!(res);
				}
			}

			Debug.WriteLine("End");
		}

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<T> Yieldable2<T, TEnum, TPred>(TEnum enumerator, TPred predicate)
			where TEnum : IEnumerator<T>
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
		public static void Test3()
		{
			int count = 0;
			for (let i in Yieldable("B.e.e.f"))
			{
				Debug.WriteLine("Char: {}", i);
				count++;
			}

			Test.Assert(count == 8);
			GC.Collect(false);
		}
	}
}
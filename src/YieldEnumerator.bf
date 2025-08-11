using System;
using System.Collections;

namespace BeefYield;

struct YieldEnumerator<T> : IEnumerator<T>, IDisposable
{
	public uint8[] mContext = null;
	public delegate Result<T>(ref int, uint8*) mGetNext = null;
	public int mState = 0;

	public void Set<TContext, TFunc>(TContext, TFunc f) mut
		where TFunc : delegate Result<T>(ref int, ref TContext context) 
	{
		mContext = new uint8[sizeof(TContext)];
		mGetNext = new (state, context) => [Inline]f(ref state, ref *(TContext*)mContext.Ptr);
	}

	public void Dispose()
	{
		delete mContext;
		delete mGetNext;
	}

	public Result<T> GetNext() mut
	{
		if (mState == -1)
			Runtime.FatalError("Enumerator re-entry not supported.");
		return mGetNext(ref mState, mContext.Ptr);
	}
}
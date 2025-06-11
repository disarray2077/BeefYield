using System;
using System.Collections;

namespace BeefYield;

struct YieldEnumerator<T> : IEnumerator<T>, IDisposable
{
	public Dictionary<StringView, uint8*> mContext = new .();
	public delegate Result<T>(ref int, ref YieldEnumerator<T>) mGetNext = null;
	public int mState = 0;

	public void Set<TFunc>(TFunc f) mut
		where TFunc : delegate Result<T>(ref int, ref YieldEnumerator<T>) 
	{
		mGetNext = new (state, context) => [Inline]f(ref state, ref context);
	}

	public ref TVar GetRef<TVar>(StringView key) mut
		where TVar : var
	{
		if (mContext.TryAdd(key, let keyPtr, let valuePtr))
		{
			*valuePtr = new uint8[sizeof(TVar)]* ();
			return ref *(TVar*)(*valuePtr);
		}
		else
		{
			return ref *(TVar*)(*valuePtr);
		}
	}

	public void Dispose()
	{
		for (let ptr in mContext.Values)
			delete ptr;
		delete mContext;
		delete mGetNext;
	}

	public Result<T> GetNext() mut
	{
		if (mState == -1)
			Runtime.FatalError("Enumerator re-entry not supported.");
		return mGetNext(ref mState, ref this);
	}
}
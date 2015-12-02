module rx.disposable;

template isDisposable(T)
{
    enum bool isDisposable = is(typeof({
            T disposable = void;
            disposable.dispose();
        }()));
}
unittest
{
    struct A { void dispose(){} }
    class B {void dispose(){} }
    interface C { void dispose(); }

    static assert(isDisposable!A);
    static assert(isDisposable!B);
    static assert(isDisposable!C);
}

interface Disposable
{
    void dispose();
}

class DisposableObject(T) : Disposable
{
public:
    this(T disposable)
    {
        _disposable = disposable;
    }

public:
    void dispose()
    {
        _disposable.dispose();
    }

private:
    T _disposable;
}

Disposable disposableObject(T)(T disposable)
{
    static assert(isDisposable!T);

    static if (is(T : Disposable))
    {
        return disposable;
    }
    else
    {
        return new DisposableObject!T(disposable);
    }
}

unittest
{
    int count = 0;
    class TestDisposable : Disposable
    {
        void dispose()
        {
            count++;
        }
    }
    auto test = new TestDisposable;
    Disposable disposable = disposableObject(test);
    assert(disposable is test);
    assert(count == 0);
    disposable.dispose();
    assert(count == 1);
}
unittest
{
    int count = 0;
    struct TestDisposable
    {
        void dispose()
        {
            count++;
        }
    }

    TestDisposable test;
    Disposable disposable = disposableObject(test);
    assert(count == 0);
    disposable.dispose();
    assert(count == 1);
}

final class NopDisposable : Disposable
{
private:
    this() { }

public:
    void dispose() { }

public:
    static Disposable instance()
    {
        import std.concurrency : initOnce;
        static __gshared NopDisposable inst;
        return initOnce!inst(new NopDisposable);
    }
}

unittest
{
    Disposable d1 = NopDisposable.instance;
    Disposable d2 = NopDisposable.instance;
    assert(d1 !is null);
    assert(d1 is d2);
}

package final class DisposedMarker : Disposable
{
private:
    this() { }

public:
    void dispose() { }

public:
    static Disposable instance()
    {
        import std.concurrency : initOnce;
        static __gshared DisposedMarker inst;
        return initOnce!inst(new DisposedMarker);
    }
}

final class SingleAssignmentDisposable : Disposable
{
public:
    void setDisposable(Disposable disposable)
    {
        import core.atomic;
        if (!cas(&_disposable, shared(Disposable).init, cast(shared)disposable)) assert(false);
    }
public:
    void dispose()
    {
        import rx.util;
        auto temp = exchange(_disposable, cast(shared)DisposedMarker.instance);
        if (temp !is null) temp.dispose();
    }
private:
    shared(Disposable) _disposable;
}
unittest
{
    static assert(isDisposable!SingleAssignmentDisposable);
}
unittest
{
    int count = 0;
    class TestDisposable : Disposable
    {
        void dispose() { count++; }
    }
    auto temp = new SingleAssignmentDisposable;
    temp.setDisposable(new TestDisposable);
    assert(count == 0);
    temp.dispose();
    assert(count == 1);
}
unittest
{
    import core.exception;
    class TestDisposable : Disposable
    {
        void dispose() { }
    }
    auto temp = new SingleAssignmentDisposable;
    temp.setDisposable(new TestDisposable);
    try
    {
        temp.setDisposable(new TestDisposable);
    }
    catch(AssertError)
    {
        return;
    }
    assert(false);
}

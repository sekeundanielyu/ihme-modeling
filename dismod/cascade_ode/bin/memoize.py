import collections
import functools
from pdb import set_trace

class memoized(object):
    '''Decorator. Caches a function's return value each time it is called.
    If called later with the same arguments, the cached value is returned
    (not reevaluated).
    '''
    def __init__(self, func):
        self.func = func
        self.cache = {}
    def __call__(self, *args, **kwds):
        key = (args,tuple(sorted(kwds.items())))
        if not isinstance(key, collections.Hashable):
            # uncacheable. a list, for instance.
            # better to not cache than blow up.
            return self.func(*args)
        if key not in self.cache:
            self.cache[key] = self.func(*args, **kwds)
        return self.cache[key]
    def __repr__(self):
        '''Return the function's docstring.'''
        return self.func.__doc__
    def __get__(self, obj, objtype):
        '''Support instance methods.'''
        return functools.partial(self.__call__, obj)

if __name__ == '__main__':
    @memoized
    def fibonacci(n):
        "Return the nth fibonacci number."
        if n in (0, 1):
            return n
        return fibonacci(n-1) + fibonacci(n-2)

    @memoized
    def fibonacci_keyed(n=0):
        "Return the nth fibonacci number."
        if n in (0, 1):
            return n
        return fibonacci_keyed(n=n-1) + fibonacci_keyed(n=n-2)

    print 'args    ', fibonacci(12)
    print 'keywords', fibonacci_keyed(n=12)

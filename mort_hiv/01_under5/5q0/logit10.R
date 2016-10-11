gbg = seq(.001,.995,.01)

lgbg = log((1-gbg)/gbg)

l10gbg = log(gbg, base = 10)

lt10gbg = log(((1-gbg)/gbg),base = 10)

lt10gbg2 = log((gbg/(1-gbg)), base = 10)

lt10gbg3 = log((gbg/(1-gbg)))/log(10)

plot(gbg, lgbg, type = "l")
lines(gbg, l10gbg)
lines(gbg, lt10gbg)
lines(gbg, lt10gbg2, col = 'red')
lines(gbg, lt10gbg3, col = 'green')

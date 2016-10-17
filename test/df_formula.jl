using Formulas
using Base.Test



## from Formulas
f = Formula(nothing, 0)
t = Terms(f)
@test t.intercept == false
@test t.response == false
@test t.terms == []
@test t.eterms == []


t = Terms(a ~ b)
@test t.terms == Term[:b]
@test t.eterms == [:a, :b]
@test t.intercept == true
@test t.response == true




## totally empty
t = Terms(Formula(nothing, 0))
@test t.response == false
@test t.intercept == false
@test t.terms == []
@test t.eterms == []

## empty RHS
t = Terms(y ~ 0)
@test t.intercept == false
@test t.terms == []
@test t.eterms == [:y]
t = Terms(y ~ -1)
@test t.intercept == false
@test t.terms == []

## intercept-only
t = Terms(y ~ 1)
@test t.response == true
@test t.intercept == true
@test t.terms == []
@test t.eterms == [:y]

## terms add
t = Terms(y ~ 1 + x1 + x2)
@test t.intercept == true
@test t.terms == Term[:x1, :x2]
@test t.eterms == [:y, :x1, :x2]

## implicit intercept behavior:
t = Terms(y ~ x1 + x2)
@test t.intercept == true
@test t.terms == Term[:x1, :x2]
@test t.eterms == [:y, :x1, :x2]

## no intercept
t = Terms(y ~ 0 + x1 + x2)
@test t.intercept == false
@test t.terms == Term[:x1, :x2]

@test t == Terms(y ~ -1 + x1 + x2) == Terms(y ~ x1 - 1 + x2) == Terms(y ~ x1 + x2 -1)

## can't subtract terms other than 1
@test_throws ErrorException Terms(y ~ x1 - x2)


t = Terms(y ~ x1 & x2)
@test t.terms == Term[:(x1 & x2)]
@test t.eterms == [:y, :x1, :x2]

## `*` expansion
t = Terms(y ~ x1 * x2)
@test t.terms == Term[:x1, :x2, :(x1 & x2)]
@test t.eterms == [:y, :x1, :x2]

## associative rule:
## +
t = Terms(y ~ x1 + x2 + x3)
@test t.terms == Term[:x1, :x2, :x3]

## &
t = Terms(y ~ x1 & x2 & x3)
@test t.terms == Term[:((&)(x1, x2, x3))]
@test t.eterms == [:y, :x1, :x2, :x3]

## distributive property of + and &
t = Terms(y ~ x1 & (x2 + x3))
@test t.terms == Term[:(x1&x2), :(x1&x3)]

t = Terms(y ~ (x1 + x2) & x3)
@test t.terms == Term[:(x1&x3), :(x2&x3)]

t = Terms(y ~ (x1 + x2) & (x3 + x4))
@test t.terms == Term[:(x1&x3), :(x1&x4), :(x2&x3), :(x2&x4)]

## three-way *
t = Terms(y ~ x1 * x2 * x3)
@test t.terms == Term[:x1, :x2, :x3,
                  :(x1&x2), :(x1&x3), :(x2&x3),
                  :((&)(x1, x2, x3))]
@test t.eterms == [:y, :x1, :x2, :x3]

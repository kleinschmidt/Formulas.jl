using Formulas
using Base.Test


@test Term(:(a+b)) == Term{:+}([Term{:a}(), Term{:b}()])
@test Term(:(a+(b+c))) == Term(:(a+b+c))
@test Term(:((a+b)+c)) == Term(:(a+b+c))
@test Term(:(a&(b&c))) == Term(:(a&b&c))
@test Term(:((a&b)&c)) == Term(:(a&b&c))

@test Term(:(a & (b+c))) == Term(:(a&b + a&c))
@test Term(:((a+b) & c)) == Term(:(a&c + b&c))
@test Term(:((a+b) & (c+d))) == Term(:(a&c + a&d + b&c + b&d))
@test Term(:(a & (b+c) & d)) == Term(:(a&b&d + a&c&d))




@test Term{:+}(Term(:(a*b))) == Term(:(a+b+a&b))
@test raise(Term(:(a*b*c))) == Term(:(a+b+c+a&b+a&c+b&c+a&b&c))

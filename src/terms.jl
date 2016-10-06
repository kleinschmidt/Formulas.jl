## Define Terms type that manages formula parsing and extension.

abstract AbstractTerm

type Term{H} <: AbstractTerm
    children::Vector{Union{Term,Symbol}}

    Term() = new(Term[])
    Term(children::Vector) = push!(new(Term[]), children...)
    Term(child::Symbol) = new([child])
end

typealias InterceptTerm Union{Term{0}, Term{-1}, Term{1}}

## equality of Terms
import Base.==
=={G,H}(::Term{G}, ::Term{H}) = false
=={H}(a::Term{H}, b::Term{H}) = a.children == b.children

function Base.show{H}(io::IO, t::Term{H})
    print(io, string(H))
    if length(t.children) > 0
        print(io, "(")
        print(io, join(map(string, t.children), ", "))
        print(io, ")")
    end
end
Base.show(io::IO, t::Term{:eval}) = print(io, string(t.children[1]))
## show ranef term:
Base.show(io::IO, t::Term{:|}) = print(io, "(", t.children[1], " | ", t.children[2], ")")

## Constructor from expression
function Term(ex::Expr)
    ex.head == :call || error("non-call expression detected: '$(ex.head)'")
    return push!(Term{ex.args[1]}(),
                 map(Term, ex.args[2:end])...)
end
Base.convert(::Type{Term}, e::Expr) = Term(e)

Term(s::Symbol) = Term{:eval}(s)
Base.convert(::Type{Term}, s::Symbol) = Term(s)
function Term(i::Integer)
    i == 0 || i == -1 || i == 1 || error("Can't construct term from Integer $i")
    Term{i}()
end

## no-op constructor
Term(t::Term) = t

## Adding children to a Term with push:
## Default: push onto children vector.
import Base.push!
function push!(t::Term, c::Term, others...)
    push!(t.children, c)
    return push!(t, others...)
end
push!(t::Term) = t


## associative rule: pushing a &() onto another &(), or +() into +()
push!(t::Term{:&}, new_child::Term{:&}, others...) =
    push!(t, new_child.children..., others...)
push!(t::Term{:+}, new_child::Term{:+}, others...) =
    push!(t, new_child.children..., others...)

## distributive property: &(a..., +(b...), c...) -> +(&(a..., b_i, c...)_i...)
push!(t::Term{:&}, new_child::Term{:+}, others...) =
    push!(Term{:+}(),
          map(c -> push!(deepcopy(t), c, others...),
              new_child.children)...)

## expand * -> main effects + interactions
Base.convert(::Type{Term{:+}}, t::Term{:*}) =
    push!(Term{:+}(),
          reduce((a,b) -> Term{:+}([a, b, Term{:&}([a, b])]),
                 t.children))

push!(t::Term, new_child::Term{:*}, others...) =
    push!(t, Term{:+}(new_child), others...)

Base.convert(::Type{Term{:+}}, t::Term) = push!(Term{:+}(), t)

## sorting term by the degree of its children: order is 1 for everything except
## interaction Term{:&} where order is number of children
degree(t::Term{:&}) = length(t.children)
degree(::Term) = 1
degree(::InterceptTerm) = 0

function Base.sort!(t::Term)
    sort!(t.children, by=degree)
    return t
end

## extract evaluation terms: children of Term{:+} and Term{:&}, nothing for
## ranef Term{:|} and intercept terms, and Term itself for everything else.
evt(t::Term) = Term[t]
evt(t::Term{:eval}) = t.children
evt(t::Term{:&}) = mapreduce(evt, vcat, t.children)
evt(t::Term{:+}) = mapreduce(evt, vcat, t.children)
evt(t::Term{:|}) = Term[]
evt(t::InterceptTerm) = Term[]

## whether a Term is for fixed effects or not
isfe(t::Term{:|}) = false
isfe(t::Term) = true


################################################################################
## Constructing a DataFrames.Terms object

type Terms
    terms::Vector
    eterms::Vector        # evaluation terms
    factors::Matrix{Int8} # maps terms to evaluation terms
    order::Vector{Int}    # orders of rhs terms
    response::Bool        # indicator of a response, which is eterms[1] if present
    intercept::Bool       # is there an intercept column in the model matrix?
end

function Terms(f::Formula)
    ## start by raising everything on the right-hand side by converting
    rhs = sort!(Term{:+}(Term(f.rhs)))
    terms = rhs.children

    ## detect intercept
    is_intercept = [isa(t, InterceptTerm) for t in terms]
    hasintercept = mapreduce(t -> isa(t, Term{1}),
                             &,
                             true, # default is to have intercept
                             terms[is_intercept])

    terms = terms[!is_intercept]
    degrees = map(degree, terms)
    
    evalterms = map(evt, terms)

    haslhs = f.lhs != nothing
    if haslhs
        lhs = Term(f.lhs)
        unshift!(evalterms, evt(lhs))
        unshift!(degrees, degree(lhs))
    end

    evalterm_sets = [Set(x) for x in evalterms]
    evalterms = unique(vcat(evalterms...))
    
    factors = Int8[t in s for t in evalterms, s in evalterm_sets]

    Terms(terms, evalterms, factors, degrees, haslhs, hasintercept)

end

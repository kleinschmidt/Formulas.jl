## Define Terms type that manages formula parsing and extension.

abstract AbstractTerm

type Term{H} <: AbstractTerm
    children::Vector{Union{Term,Symbol}}

    Term() = new(Term[])
    Term(children::Vector) = add_children!(new(Term[]), children)
    Term(child::Symbol) = new([child])
end

typealias InterceptTerm Union{Term{0}, Term{-1}, Term{1}}

## equality of Terms
import Base.==
=={G,H}(::Term{G}, ::Term{H}) = false
=={H}(a::Term{H}, b::Term{H}) = a.children == b.children

## display of terms
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

## Converting to Term:

## Symbols are converted to :eval terms (leaf nodes)
Base.convert(::Type{Term}, s::Symbol) = Term{:eval}(s)

## Integers to intercept terms
function Term(i::Integer)
    i == 0 || i == -1 || i == 1 || error("Can't construct term from Integer $i")
    Term{i}()
end

## no-op constructor
Term{H}(t::Term{H}) = t

## convert from one head type to another
(::Type{Term{H}}){H,J}(t::Term{J}) = add_children!(Term{H}(), t, [])

## Expressions are recursively converted to Terms, depth-first, and then added
## as children.  Specific `add_children!` methods handle special cases like
## associative and distributive operators.
function Base.convert(::Type{Term}, ex::Expr)
    ex.head == :call || error("non-call expression detected: '$(ex.head)'")
    add_children!(Term{ex.args[1]}(), [Term(a) for a in ex.args[2:end]])
end


## Adding children to a Term

## General strategy: add one at a time to allow for dispatching on special
## cases, but also keep track of the rest of the children being added because at
## least the distributive rule requires that context.
add_children!(t::Term, new_children::Vector) =
    isempty(new_children) ?
    t :
    add_children!(t::Term, new_children[1], new_children[2:end])

function add_children!(t::Term, c::Term, others::Vector)
    push!(t.children, c)
    add_children!(t, others)
end

## special cases:
## Associative rule
add_children!(t::Term{:+}, new_child::Term{:+}, others::Vector) =
    add_children!(t, cat(1, new_child.children, others))
add_children!(t::Term{:&}, new_child::Term{:&}, others::Vector) =
    add_children!(t, cat(1, new_child.children, others))

## Distributive property
## &(a..., +(b...), c...) -> +(&(a..., b_i, c...)_i...)
add_children!(t::Term{:&}, new_child::Term{:+}, others::Vector) =
    Term{:+}([add_children!(deepcopy(t), c, others) for c in new_child.children])

## Expansion of a*b -> a + b + a&b
expand_star(a::Term,b::Term) = Term{:+}([a, b, Term{:&}([a,b])])
add_children!(t::Term, new_child::Term{:*}, others::Vector) =
    add_children!(Term{:+}(reduce(expand_star, new_child.children)), others)

## Handle - for intercept term -1, and throw error otherwise
add_children!(t::Term{:-}, children::Vector) =
    isa(children[2], Term{1}) ?
    Term{:+}([children[1], Term{-1}()]) :
    error("invalid subtraction of $(children[2]); subtraction only supported for -1")

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
    factors::Matrix{Bool} # maps terms to evaluation terms
    ## An eterms x terms matrix which is true for terms that need to be "promoted"
    ## to full rank in constructing a model matrx
    is_non_redundant::Matrix{Bool}
# order can probably be dropped.  It is vec(sum(factors, 1))
    order::Vector{Int}    # orders of rhs terms
    response::Bool        # indicator of a response, which is eterms[1] if present
    intercept::Bool       # is there an intercept column in the model matrix?
end

Base.:(==)(t1::Terms, t2::Terms) = all(getfield(t1, f)==getfield(t2, f) for f in fieldnames(t1))

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
    non_redundants = fill(false, size(factors)) # initialize to false

    Terms(terms, evalterms, factors, non_redundants, degrees, haslhs, hasintercept)

end

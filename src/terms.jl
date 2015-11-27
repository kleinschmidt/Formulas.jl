## Define Terms type that manages formula parsing and extension.

abstract AbstractTerm

type Term{H} <: AbstractTerm
    children::Vector{Term}

    Term() = new(Term[])
    Term(children::Vector{Term}) = push!(new(Term[]), children...)
end

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

## Constructor from expression
import Base.convert
function convert(::Type{Term}, ex::Expr)
    ex.head == :call || error("non-call expression detected")
    return push!(Term{ex.args[1]}(),
                 map(child -> convert(Term, child), ex.args[2:end])...)
end
## Constructor from symbol (leaves)
convert(::Type{Term}, s::Symbol) = Term{s}()



## Adding children to a Term with push:
## Default: push onto children vector.
import Base.push!
function push!(t::Term, c::Term, others...)
    push!(t.children, c)
    return push!(t, others...)
end
push!(t::Term) = t


## associative rule: pushing a &() onto another &(), or +() into +()
push!(t::Term{:&}, new_child::Term{:&}, others...) = push!(t, new_child.children..., others...)
push!(t::Term{:+}, new_child::Term{:+}, others...) = push!(t, new_child.children..., others...)

## distributive property: &(a..., +(b...), c...) -> +(&(a..., b_i, c...)_i)
push!(t::Term{:&}, new_child::Term{:+}, others...) =
    push!(Term{:+}(),
          map(c -> push!(deepcopy(t), c, others...),
              new_child.children)...)

## expand * -> main effects + interactions
convert(::Type{Term{:+}}, t::Term{:*}) =
    push!(Term{:+}(),
          reduce((a,b) -> Term{:+}([a, b, Term{:&}([a, b])]),
                 t.children))

push!(t::Term, new_child::Term{:*}, others...) =
    push!(t, Term{:+}(new_child), others...)



using Base.Meta
using JuMP: _valid_model, _error_if_cannot_register, object_dictionary, variable_type
using JuMP.Containers

# Parse raw input to define the upper bound for an interval set
function _parse_one_operator_parameter(
    _error::Function, infoexpr::_ParameterInfoExpr, ::Union{Val{:<=}, Val{:≤}},
    upper)
    _set_upper_bound_or_error(_error, infoexpr, upper)
end

# Parse raw input to define the lower bound for an interval set
function _parse_one_operator_parameter(
    _error::Function, infoexpr::_ParameterInfoExpr, ::Union{Val{:>=}, Val{:≥}},
    lower)
    _set_lower_bound_or_error(_error, infoexpr, lower)
end

# Parse raw input to define the distribution for a dist set
function _parse_one_operator_parameter(
    _error::Function, infoexpr::_ParameterInfoExpr, ::Union{Val{:in}, Val{:∈}},
    value)
    # check if interval set
    if isexpr(value.args[1], :vect)
        _set_lower_bound_or_error(_error, infoexpr,
                                  _esc_non_constant(value.args[1].args[1]))
        _set_upper_bound_or_error(_error, infoexpr,
                                  _esc_non_constant(value.args[1].args[2]))
    else
        _set_or_error(_error, infoexpr, value)
    end
end

# Default function for unrecognized operators
function _parse_one_operator_parameter(
    _error::Function, infoexpr::_ParameterInfoExpr, ::Val{S}, value) where S
    _error("Unknown sense $S.")
end

# In that case we assume the variable is the lhs.
function _parse_parameter(_error::Function, infoexpr::_ParameterInfoExpr,
                          sense::Symbol, var, value)
    _parse_one_operator_parameter(_error, infoexpr, Val(sense),
                                _esc_non_constant(value))
    return var
end

# If the lhs is a number and not the rhs, we can deduce that the rhs is
# the variable.
function _parse_parameter(_error::Function, infoexpr::_ParameterInfoExpr,
                          sense::Symbol, value::Number, var)
    _parse_one_operator_parameter(_error, infoexpr,
                                  JuMP.reverse_sense(Val(sense)),
                                  _esc_non_constant(value))
    return var
end

# Parse raw input to define the upper and lower bounds for an interval set
function _parse_ternary_parameter(_error::Function, infoexpr::_ParameterInfoExpr,
                                  ::Union{Val{:<=}, Val{:≤}}, lower,
                                  ::Union{Val{:<=}, Val{:≤}}, upper)
    _set_lower_bound_or_error(_error, infoexpr, lower)
    _set_upper_bound_or_error(_error, infoexpr, upper)
end

# Parse raw input to define the upper and lower bounds for an interval set
function _parse_ternary_parameter(_error::Function, infoexpr::_ParameterInfoExpr,
                                  ::Union{Val{:>=}, Val{:≥}}, upper,
                                  ::Union{Val{:>=}, Val{:≥}}, lower)
    _parse_ternary_parameter(_error, infoexpr, Val(:≤), lower, Val(:≤), upper)
end

# Default for unrecognized operators
function _parse_ternary_parameter(_error::Function, infoexpr::_ParameterInfoExpr,
                                  ::Val, lvalue, ::Val, rvalue)
    _error("Use the form lb <= ... <= ub.")
end

# Interpret a param_expr from macro input
function _parse_parameter(_error::Function, infoexpr::_ParameterInfoExpr, lvalue,
                          lsign::Symbol, var, rsign::Symbol, rvalue)
    # lvalue lsign var rsign rvalue
    _parse_ternary_parameter(_error, infoexpr, Val(lsign),
                             _esc_non_constant(lvalue), Val(rsign),
                             _esc_non_constant(rvalue))
    return var
end

"""
    @independent_parameter(model::InfiniteModel, kw_args...)::GeneralVariableRef

Add an *anonymous* infinite parameter to the model `model` described by the
keyword arguments `kw_args` and returns the parameter reference.

```julia
@independent_parameter(model::InfiniteModel, expr, kw_args...)::GeneralVariableRef
```

Add a parameter to the model `model` described by the expression `expr`
and the keyword arguments `kw_args`. (note that in
the following the symbol `<=` can be used instead of `≤`, the symbol `>=`can
be used instead of `≥`, and the symbol `in` can be used instead of `∈`) The
expression `expr` can be of the form:
- `paramexpr` creating parameters described by `paramexpr`.
- `lb ≤ paramexpr ≤ ub` creating parameters described by `paramexpr` characterized
   by a continuous interval set with lower bound `lb` and upper bound `ub`.
- `paramexpr ∈ [lb, ub]` creating parameters described by `paramexpr` characterized
   by a continuous interval set with lower bound `lb` and upper bound `ub`.
- `paramexpr ∈ dist` creating parameters described by `paramexpr` characterized
   by the `Distributions.jl` distribution object `dist`.

The expression `paramexpr` can be of the form:
- `paramname` creating a scalar parameter of name `paramname`
- `paramname[...]` or `[...]` creating a container of parameters

The recognized keyword arguments in `kw_args` are the following:
- `base_name`: Sets the name prefix used to generate parameter names. It
  corresponds to the parameter name for scalar parameter, otherwise, the
  parameter names are set to `base_name[...]` for each index `...` of the axes
  `axes`.
- `lower_bound`: Sets the value of the parameter lower bound for an interval set.
- `upper_bound`: Sets the value of the parameter upper bound for an interval set.
- `set`: The `InfiniteSet` characterizing the parameters see [`IntervalSet`](@ref)
   and [`UniDistributionSet`](@ref).
- `distribution`: Sets the `Distributions.jl` distribution object that characterizes
  the parameters.
- `supports`: Sets the support points for the parameters.
- `num_supports`: Specifies the number of supports to be automatically generated.
                  Note that `supports` takes precedence. Defaults to `DefaultNumSupports`.
- `derivative_method`: Specifies the numerical method used to evaluate derivatives that 
                       are taken with respect to the parameter.
- `sig_digits`: Specifies the number of significant digits that should be used
              in automatic support generation. Defaults to `DefaultSigDigits`.
- `container`: Specify the container type. Defaults to `automatic`

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP, Distributions; m = InfiniteModel())
julia> @independent_parameter(m, x in [0, 1])
x

julia> @independent_parameter(m, y[i = 1:2] in Normal(), num_supports = 10)
2-element Array{GeneralVariableRef,1}:
 y[1]
 y[2]

julia> z = @independent_parameter(m, [["a", "b"]], lower_bound = 0,
                                  upper_bound = 1, supports = [0, 0.5, 1])
1-dimensional DenseAxisArray{GeneralVariableRef,1,...} with index sets:
   Dimension 1, ["a", "b"]
And data, a 2-element Array{GeneralVariableRef,1}:
noname[a]
noname[b]
```
"""
macro independent_parameter(model, args...)
    esc_model = esc(model)

    extra, kw_args, requestedcontainer = _extract_kw_args(args)

    # check to see if error_args are provided define error function
    error_kwargs = filter(kw -> kw.args[1] == :error_func, kw_args)
    if isempty(error_kwargs)
        _error(str...) = _macro_error(:independent_parameter, (model, args...), 
                                      __source__, str...)
    else
        _error = error_kwargs[1].args[2]
    end

    # if there is only a single non-keyword argument, this is an anonymous
    # variable spec and the one non-kwarg is the model
    if length(extra) == 0
        x = gensym()
        anon_singleton = true
    elseif length(extra) == 1
        x = popfirst!(extra)
        anon_singleton = false
    else
        x = popfirst!(extra)
        arg = popfirst!(extra)
        _error("Unrecognized argument $arg provided.")
    end

    info_kw_args = filter(InfiniteOpt._is_set_keyword, kw_args)
    extra_kw_args = filter(kw -> kw.args[1] != :base_name && 
                           !InfiniteOpt._is_set_keyword(kw) && 
                           kw.args[1] != :error_func, kw_args)
    base_name_kw_args = filter(kw -> kw.args[1] == :base_name, kw_args)
    infoexpr = InfiniteOpt._ParameterInfoExpr(; JuMP._keywordify.(info_kw_args)...)

    # There are five cases to consider:
    # x                                         | type of x | x.head
    # ------------------------------------------+-----------+------------
    # param                                       | Symbol    | NA
    # param in [lb, ub]                           | Expr      | :call
    # lb <= param <= ub                           | Expr      | :comparison
    explicit_comparison = InfiniteOpt.isexpr(x, :comparison) || InfiniteOpt.isexpr(x, :call)
    if explicit_comparison
        param = InfiniteOpt._parse_parameter(_error, infoexpr, x.args...)
    else
        param = x
    end

    anonvar = InfiniteOpt.isexpr(param, :vect) || InfiniteOpt.isexpr(param, :vcat) || anon_singleton
    anonvar && explicit_comparison && _error("Cannot use explicit bounds via " *
                                             ">=, <= with an anonymous parameter")
    parameter = gensym()
    name = JuMPC._get_name(param)
    if isempty(base_name_kw_args)
        base_name = anonvar ? "" : string(name)
    else
        base_name = esc(base_name_kw_args[1].args[2])
    end

    if !isa(name, Symbol) && !anonvar
        _error("Expression $name should not be used as a parameter name. Use " *
               "the \"anonymous\" syntax $name = @independent_parameter(model, " *
               "...) instead.")
    end

    set = InfiniteOpt._constructor_set(_error, infoexpr)
    if isa(param, Symbol)
        # Easy case - a single variable
        buildcall = :( build_parameter($_error, $set) )
        JuMP._add_kw_args(buildcall, extra_kw_args)
        parametercall = :( add_parameter($esc_model, $buildcall, $base_name) )
        creationcode = :($parameter = $parametercall)
    else
        # isa(param, Expr) || _error("Expected $param to be a parameter name") --> not needed... I think
        # We now build the code to generate the variables (and possibly the
        # SparseAxisArray to contain them)
        idxvars, indices = JuMPC._build_ref_sets(_error, param)
        buildcall = :( build_parameter($_error, $set) )
        JuMP._add_kw_args(buildcall, extra_kw_args)
        parametercall = :( add_parameter($esc_model, $buildcall,
                                         $(_name_call(base_name, idxvars))) )
        creationcode = JuMPC.container_code(idxvars, indices, parametercall,
                                             requestedcontainer)
    end
    if anonvar
        # Anonymous variable, no need to register it in the model-level
        # dictionary nor to assign it to a variable in the user scope.
        # We simply return the variable
        macro_code = creationcode
    else
        # We register the variable reference to its name and
        # we assign it to a variable in the local scope of this name
        macro_code = JuMP._macro_assign_and_return(creationcode, parameter, name,
                                                   model_for_registering = esc_model)
    end
    return JuMP._finalize_macro(esc_model, macro_code, __source__)
end

"""
    @finite_parameter(model::InfiniteModel, value)::GeneralVariableRef

Define and add an anonymous finite parameter to `model` and return its
parameter reference. Its value is equal to `value`.

```julia
    @finite_parameter(model::InfiniteModel, param_expr,
                      value_expr)::GeneralVariableRef
```
Define and add a finite parameter(s) to `model` and return appropriate parameter
reference(s). The parameter(s) has/have value(s) indicated by the `value_expr`.
The expression `param_expr` can be of the form:
- `paramname` creating a scalar parameter of name `paramname`
- `paramname[...]` or `[...]` creating a container of parameters

The expression `value_expr` simply expresses the value of the parameter(s). This
is typically a number but could be an array indexed using an index defined in
`param_expr`.

The recognized keyword arguments in `kw_args` are the following:
- `base_name`: Sets the name prefix used to generate parameter names. It
  corresponds to the parameter name for scalar parameter, otherwise, the
  parameter names are set to `base_name[...]` for each index `...` of the axes
  `axes`.
- `container`: Specify the container type.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> par = @finite_parameter(model, 2)
noname

julia> vals = [3, 2];

julia> pars = @finite_parameter(model, [i = 1:2], vals[i], base_name = "par")
2-element Array{ParameterRef,1}:
 par[1]
 par[2]

julia> @finite_parameter(model, par2, 42)
par2
```
"""
macro finite_parameter(model, args...)
    esc_model = esc(model)

    extra, kw_args, requestedcontainer = _extract_kw_args(args)

    macro_name = :finite_parameter
    _error(str...) = _macro_error(macro_name, (model, args...), __source__, str...)

    # if there is only a single non-keyword argument, this is an anonymous
    # variable spec and the one non-kwarg is the model

    if length(extra) == 1
        param = gensym()
        value = popfirst!(extra)
        anon_singleton = true
    elseif length(extra) == 2
        param = popfirst!(extra)
        value = popfirst!(extra)
        anon_singleton = false
    else
        _error("Incorrect number of arguments. Must be of form " *
               "@finite_parameter(model, name_expr, value).")
    end
    value = _esc_non_constant(value)

    extra_kw_args = filter(kw -> kw.args[1] != :base_name, kw_args)
    base_name_kw_args = filter(kw -> kw.args[1] == :base_name, kw_args)

    anonvar = isexpr(param, :vect) || isexpr(param, :vcat) || anon_singleton

    parameter = gensym()
    name = JuMPC._get_name(param)
    if isempty(base_name_kw_args)
        base_name = anonvar ? "" : string(name)
    else
        base_name = esc(base_name_kw_args[1].args[2])
    end

    if !isa(name, Symbol) && !anonvar
        _error("Expression $name should not be used as a parameter name. Use " *
               "the \"anonymous\" syntax $name = @finite_parameter(model, " *
               "...) instead.")
    end

    if isa(param, Symbol)
        buildcall = :( build_parameter($_error, $value) )
        JuMP._add_kw_args(buildcall, extra_kw_args)
        parametercall = :( add_parameter($esc_model, $buildcall, $base_name) )
        creationcode = :($parameter = $parametercall)
    else
        idxvars, indices = JuMPC._build_ref_sets(_error, param)
        buildcall = :( build_parameter($_error, $value) )
        JuMP._add_kw_args(buildcall, extra_kw_args)
        parametercall = :( add_parameter($esc_model, $buildcall,
                                         $(_name_call(base_name, idxvars))) )
        creationcode = JuMPC.container_code(idxvars, indices, parametercall,
                                             requestedcontainer)
    end
    if anonvar
        macro_code = creationcode
    else
        macro_code = JuMP._macro_assign_and_return(creationcode, parameter, name,
                                                   model_for_registering = esc_model)
    end
    return JuMP._finalize_macro(esc_model, macro_code, __source__)
end

"""
    @dependent_parameters(model::InfiniteModel, kw_args...)::GeneralVariableRef

Add *anonymous* dependent infinite parameters to the model `model` described by
the keyword arguments `kw_args` and returns the container of parameter references.

```julia
@dependent_parameters(model::InfiniteModel, expr, kw_args...)::GeneralVariableRef
```

Add a container of dependent infinite parameters to the model `model` described
by the expression `expr`, and the keyword arguments `kw_args`. (note that in
the following the symbol `<=` can be used instead of `≤`, the symbol `>=`can
be used instead of `≥`, and the symbol `in` can be used instead of `∈`) The
expression `expr` can be of the form:
- `paramexpr` creating parameters described by `paramexpr`.
- `lb ≤ paramexpr ≤ ub` creating parameters described by `paramexpr` characterized
   by a continuous interval set with lower bound `lb` and upper bound `ub`.
- `paramexpr ∈ [lb, ub]` creating parameters described by `paramexpr` characterized
   by a continuous interval set with lower bound `lb` and upper bound `ub`.
- `paramexpr ∈ dist` creating parameters described by `paramexpr` characterized
   by the `Distributions.jl` distribution object `dist`.
- `paramexpr ∈ set` creating parameters described by `paramexpr` characterized
   by the `AbstractInfiniteSet` object `set`.

The expression `paramexpr` must be of the form:
- `paramname[...]` or `[...]` creating a container of parameters

The recognized keyword arguments in `kw_args` are the following:
- `base_name`: Sets the name prefix used to generate parameter names. It
  corresponds to the parameter name for scalar parameter, otherwise, the
  parameter names are set to `base_name[...]` for each index `...` of the axes
  `axes`.
- `lower_bound`: Sets the value of the parameter lower bound for an interval set.
- `upper_bound`: Sets the value of the parameter upper bound for an interval set.
- `set`: The `InfiniteSet` characterizing the parameters that are subtypes of
         [`AbstractInfiniteSet`](@ref).
- `distribution`: Sets the `Distributions.jl` distribution object that characterizes
  the parameters.
- `supports`: Sets the support points for the parameters.
- `num_supports`: Specifies the number of supports to be automatically generated.
                  Note that `supports` takes precedence. Defaults to `DefaultNumSupports`.
- `derivative_method`: Specifies the numerical derivative method used to evaluate 
                       derivatives that depend on a particular dependent parameter.
- `sig_digits`: Specifies the number of significant digits that should be used
              in automatic support generation. Defaults to `DefaultSigDigits`.
- `container`: Specify the container type. Defaults to `automatic`.

**Examples**
```julia-repl
julia> @dependent_parameters(m, x[1:2] in [0, 1])
2-element Array{GeneralVariableRef,1}:
 x[1]
 x[2]

julia> @dependent_parameters(m, y[i = 1:2] in MvNormal(ones(2)), num_supports = 10)
2-element Array{GeneralVariableRef,1}:
 y[1]
 y[2]

julia> z = @dependent_parameters(m, [i = ["a", "b"], j = 1:2],
                                 distribution = MatrixBeta(2, 2, 2))
2-dimensional DenseAxisArray{GeneralVariableRef,2,...} with index sets:
    Dimension 1, ["a", "b"]
    Dimension 2, Base.OneTo(2)
And data, a 2×2 Array{GeneralVariableRef,2}:
 noname[a,1]  noname[a,2]
 noname[b,1]  noname[b,2]
```
"""
macro dependent_parameters(model, args...)
    # extract the raw arguments
    esc_model = esc(model)
    extra, kw_args, requestedcontainer = _extract_kw_args(args)

    # check to see if error_args are provided define error function
    error_kwargs = filter(kw -> kw.args[1] == :error_func, kw_args)
    if isempty(error_kwargs)
        _error(str...) = _macro_error(:dependent_parameters, (model, args...), 
                                      __source__, str...)
    else
        _error = error_kwargs[1].args[2]
    end

    # there must be one extra positional argument to specify the dimensions
    if length(extra) == 1
        x = popfirst!(extra) 
    elseif length(extra) == 0
        _error("Must specify more than one dependent parameter.")
    else
        x = popfirst!(extra)
        arg = popfirst!(extra)
        _error("Unrecognized argument $arg provided.")
    end

    # parse the keyword arguments
    info_kw_args = filter(_is_set_keyword, kw_args)
    supports_kw_arg = filter(kw -> kw.args[1] == :supports, kw_args)
    method_kw_arg = filter(kw -> kw.args[1] == :derivative_method, kw_args)
    extra_kw_args = filter(kw -> kw.args[1] != :base_name &&
                           !InfiniteOpt._is_set_keyword(kw) &&
                           kw.args[1] != :error_func &&
                           kw.args[1] != :supports &&
                           kw.args[1] != :derivative_method, kw_args)
    base_name_kw_args = filter(kw -> kw.args[1] == :base_name, kw_args)
    infoexpr = InfiniteOpt._ParameterInfoExpr(; JuMP._keywordify.(info_kw_args)...)

    # There are six cases to consider:
    # x                                         | type of x | x.head
    # ------------------------------------------+-----------+------------
    # param                                       | Symbol    | NA
    # [1:2]                                       | Expr      | :vect
    # param[1:2]                                  | Expr      | :ref
    # param[1:2] <= ub                            | Expr      | :call
    # param[1:2] in [lb, ub] (other sets)         | Expr      | :call
    # lb <= param[1:2] <= ub                      | Expr      | :comparison
    # In the three last cases, we call parse_variable
    symbolic_set = isexpr(x, :comparison) || isexpr(x, :call)
    if symbolic_set
        param = InfiniteOpt._parse_parameter(_error, infoexpr, x.args...)
    elseif isa(x, Symbol)
        _error("Must specify more than one dependent parameter.")
    else
        param = x
    end

    # determine it is an anonymous call
    anonparam = isexpr(param, :vcat) || isexpr(param, :vect)
    anonparam && symbolic_set && _error("Cannot use symbolic infinite defintion " *
                                        "with an anonymous parameter")
    # process the parameter name
    parameter = gensym()
    name = JuMPC._get_name(param)
    if isempty(base_name_kw_args)
        base_name = anonparam ? "" : string(name)
    else
        base_name = esc(base_name_kw_args[1].args[2])
    end
    if !isa(name, Symbol) && !anonparam
        _error("Expression $name should not be used as a parameter name. Use " *
               "the \"anonymous\" syntax $name = @dependent_parameters(model, " *
               "...) instead.")
    end

    # process the supports
    if isempty(supports_kw_arg)
        supports = :(Float64[])
    else
        supports = esc(supports_kw_arg[1].args[2])
    end

    # process the derivative methods
    if isempty(method_kw_arg)
        method = :(InfiniteOpt.DefaultDerivativeMethod)
    else
        method = esc(method_kw_arg[1].args[2])
    end

    # parse the infinite set(s)
    set = InfiniteOpt._construct_array_set(_error, infoexpr)

    # make code to build the DependentParameters object and the references
    idxvars, indices = JuMPC._build_ref_sets(_error, param)
    namecode = _name_call(base_name, idxvars)
    parambuildcall = :( InfiniteOpt._DependentParameter($set, $supports, $namecode, $method) )
    param_container_call = JuMPC.container_code(idxvars, indices, parambuildcall,
                                                requestedcontainer)
    buildcall = :( InfiniteOpt._build_parameters($_error, $param_container_call) )
    JuMP._add_kw_args(buildcall, extra_kw_args)
    creationcode = :( add_parameters($esc_model, $(buildcall)...) )

    # make the final return code based on if it is anonymous or not
    if anonparam
        macro_code = creationcode
    else
        macro_code = JuMP._macro_assign_and_return(creationcode, parameter, name,
                                                   model_for_registering = esc_model)
    end
    return JuMP._finalize_macro(esc_model, macro_code, __source__)
end

"""
    @infinite_parameter(model::InfiniteModel, kw_args...)::GeneralVariableRef

Add *anonymous* infinite parameter to the model `model` described by
the keyword arguments `kw_args` and returns the parameter reference.

```julia
@infinite_parameter(model::InfiniteModel, expr, kw_args...)::GeneralVariableRef
```

Add an infinite parameter to the model `model` described by the expression `expr`,
and the keyword arguments `kw_args`. This is just a wrapper macro that will make
the appropriate call to either [`@independent_parameter`](@ref) or
[`@dependent_parameters`](@ref). (Note that in
the following the symbol `<=` can be used instead of `≤`, the symbol `>=`can
be used instead of `≥`, and the symbol `in` can be used instead of `∈`) The
expression `expr` can be of the form:
- `paramexpr` creating parameters described by `paramexpr`.
- `lb ≤ paramexpr ≤ ub` creating parameters described by `paramexpr` characterized
   by a continuous interval set with lower bound `lb` and upper bound `ub`.
- `paramexpr ∈ [lb, ub]` creating parameters described by `paramexpr` characterized
   by a continuous interval set with lower bound `lb` and upper bound `ub`.
- `paramexpr ∈ dist` creating parameters described by `paramexpr` characterized
   by the `Distributions.jl` distribution object `dist`.
- `paramexpr ∈ set` creating parameters described by `paramexpr` characterized
  by the `AbstractInfiniteSet` object `set`.

The expression `paramexpr` can be of the form:
- `paramname` creating a scalar parameter of name `paramname`
- `paramname[...]` or `[...]` creating a container of parameters

The recognized keyword arguments in `kw_args` are the following:
- `base_name`: Sets the name prefix used to generate parameter names. It
  corresponds to the parameter name for scalar parameter, otherwise, the
  parameter names are set to `base_name[...]` for each index `...` of the axes
  `axes`.
- `lower_bound`: Sets the value of the parameter lower bound for an interval set.
- `upper_bound`: Sets the value of the parameter upper bound for an interval set.
- `set`: The `InfiniteSet` characterizing the parameters see subtypes of
         [`AbstractInfiniteSet`](@ref).
- `distribution`: Sets the `Distributions.jl` distribution object that characterizes
  the parameters.
- `supports`: Sets the support points for the parameters.
- `num_supports`: Specifies the number of supports to be automatically generated.
                  Note that `supports` takes precedence. Defaults to `DefaultNumSupports`.
- `derivative_method`: Specify the numerical method to evaluate derivatives that are
                       taken with respect to the parameter.
- `sig_digits`: Specifies the number of significant digits that should be used
              in automatic support generation. Defaults to `DefaultSigDigits`.
- `independent`: Specifies if the each parameter is independent from each other
  or not. Defaults to false.
- `container`: Specify the container type. Defaults to `automatic`

**Examples**
```julia-repl
julia> @infinite_parameter(m, x in [0, 1])
x

julia> @infinite_parameter(m, y[i = 1:2] in MvNormal(ones(2)), num_supports = 10)
2-element Array{GeneralVariableRef,1}:
 y[1]
 y[2]

julia> z = @infinite_parameter(m, [["a", "b"]], distribution = Normal(),
                               independent = true)
1-dimensional DenseAxisArray{GeneralVariableRef,1,...} with index sets:
    Dimension 1, ["a", "b"]
And data, a 2-element Array{GeneralVariableRef,1}:
 noname[a]
 noname[b]
```
"""
macro infinite_parameter(model, args...)
    # define error message function
    _error(str...) = _macro_error(:infinite_parameter, (model, args...),
                                  __source__, str...)
    # parse the arguments
    extra, kw_args, requestedcontainer = _extract_kw_args(args)
    indep_kwarg = filter(kw -> kw.args[1] == :independent, kw_args)
    new_kwargs = filter(kw -> kw.args[1] != :independent, kw_args)
    if isempty(indep_kwarg)
        independent = false
    else
        independent = indep_kwarg[1].args[2]
    end

    # determine if there is only one parameter
    if length(extra) == 0
        code = :( @independent_parameter($model, $(extra...), $(new_kwargs...),
                                         container = $requestedcontainer,
                                         error_func = $(_error)) )
    else
        # get the param expression and check it is an array --> TODO make more efficient
        x = first(extra)
        infoexpr = InfiniteOpt._ParameterInfoExpr()
        symbolic_set = isexpr(x, :comparison) || isexpr(x, :call)
        if symbolic_set
            param = InfiniteOpt._parse_parameter(_error, infoexpr, x.args...)
        else
            param = x
        end
        if param isa Symbol
            code = :( @independent_parameter($model, $(extra...), $(new_kwargs...),
                                             container = $requestedcontainer,
                                             error_func = $(_error)) )
        else
            code = quote
                if $independent
                    @independent_parameter($model, $(extra...), $(new_kwargs...),
                                           container = $requestedcontainer,
                                           error_func = $(_error))
                else
                    @dependent_parameters($model, $(extra...), $(new_kwargs...),
                                          container = $requestedcontainer,
                                          error_func = $(_error))
                end
            end
        end
    end
    return esc(code)
end

## Define helper functions needed to parse infinite variable expressions
# Check rhs to to ensure is not a variable as best we can
function _check_rhs(arg1, arg2)
    if isexpr(arg2, :ref)
        if isexpr(arg2.args[2], :kw)
            temp = arg2
            arg2 = arg1
            arg1 = temp
        end
    # elseif isexpr(arg2, :call) --> infinite loop if both sides are :calls
    #     temp = arg2
    #     arg2 = arg1
    #     arg1 = temp
    end
    return arg1, arg2
end

# Assume variable on lhs, but check if swapped
function _less_than_parse(arg1, arg2)
    # check if swapped
    arg1_orig = arg1
    arg1, arg2 = _check_rhs(arg1, arg2)
    if arg1 != arg1_orig
        return _greater_than_parse(arg1, arg2)
    end
    # check if has parameter tuple
    if isexpr(arg1, :call)
        return Expr(:call, :<=, arg1.args[1], arg2),
                    Expr(:tuple, arg1.args[2:end]...)
    else
        return Expr(:call, :<=, arg1, arg2), nothing
    end
end

# Assume variable on lhs, but check if swapped
function _greater_than_parse(arg1, arg2)
    # check if swapped
    arg1_orig = arg1
    arg1, arg2 = _check_rhs(arg1, arg2)
    if arg1 != arg1_orig
        return _less_than_parse(arg1, arg2)
    end
    # check if has parameter tuple
    if isexpr(arg1, :call)
        return Expr(:call, :>=, arg1.args[1], arg2),
                    Expr(:tuple, arg1.args[2:end]...)
    else
        return Expr(:call, :>=, arg1, arg2), nothing
    end
end

# The variable is on the rhs
function _less_than_parse(arg1::Number, arg2)
    return _greater_than_parse(arg2, arg1)
end

# The variable is on the rhs
function _greater_than_parse(arg1::Number, arg2)
    return _less_than_parse(arg2, arg1)
end

# Assume variable on lhs
function _equal_to_parse(arg1, arg2)
    arg1, arg2 = _check_rhs(arg1, arg2)
    if isexpr(arg1, :call)
        return Expr(:call, :(==), arg1.args[1], arg2),
                    Expr(:tuple, arg1.args[2:end]...)
    else
        return Expr(:call, :(==), arg1, arg2), nothing
    end
end

# The variable is on the rhs
function _equal_to_parse(arg1::Number, arg2)
    return _equal_to_parse(arg2, arg1)
end

# Return the tuple of form (var_expr, param_tuple_expr)
function _parse_parameters(_error::Function, head::Val{:call}, args)
    if args[1] in [:<=, :≤]
        return _less_than_parse(args[2], args[3])
    elseif args[1] in [:>=, :≥]
        return _greater_than_parse(args[2], args[3])
    elseif args[1] == :(==)
        return _equal_to_parse(args[2], args[3])
    elseif !(args[1] in [:in, :∈])
        return args[1], Expr(:tuple, args[2:end]...)
    else
        first = args[1]
        _error("Invalid operator $first.")
    end
end

# Return the tuple of form (var_expr, param_tuple_expr)
function _parse_parameters(_error::Function, head::Val{:comparison}, args)
    if isexpr(args[3], :call)
        return Expr(:comparison, args[1:2]..., args[3].args[1], args[4:5]...),
                    Expr(:tuple, args[3].args[2:end]...)
    else
        return Expr(:comparison, args...), nothing
    end
end

"""
    @infinte_variable(model::InfiniteModel, kw_args...)::GeneralVariableRef

Add an *anonymous* infinite variable to the model `model` described by the
keyword arguments `kw_args` and returns the variable reference. Note that the
`parameter_refs` keyword is required in this case.

```julia
@infinite_variable(model::InfiniteModel, varexpr, args...,
                   kw_args...)::GeneralVariableRef
```

Add an infinite variable to `model` described by the expression `var_expr`, the
positional arguments `args` and the keyword arguments `kw_args`. The expression
`varexpr` can either be (note that in the following the symbol `<=` can be used
instead of `≤` and the symbol `>=`can be used instead of `≥`) of the form:

- `varexpr` creating variables described by `varexpr`
- `varexpr ≤ ub` (resp. `varexpr ≥ lb`) creating variables described by
  `varexpr` with upper bounds given by `ub` (resp. lower bounds given by `lb`)
- `varexpr == value` creating variables described by `varexpr` with fixed values
   given by `value`
- `lb ≤ varexpr ≤ ub` or `ub ≥ varexpr ≥ lb` creating variables described by
  `varexpr` with lower bounds given by `lb` and upper bounds given by `ub`

The expression `varexpr` can be of the form:

- `varname` creating a scalar real variable of name `varname`
- `varname(params...)` creating a scalar real variable of name `varname` with
  infinite parameters `params...` see `parameter_refs` for format.
- `varname[...]` or `[...]` creating a container of variables.
- `varname[...](params...)` or `[...]` creating a container of variables with
  infinite parameters `params...` in the first case.

The recognized positional arguments in `args` are the following:

- `Bin`: Sets the variable to be binary, i.e. either 0 or 1.
- `Int`: Sets the variable to be integer, i.e. one of ..., -2, -1, 0, 1, 2, ...

The recognized keyword arguments in `kw_args` are the following:

- `parameter_refs`: This is mandatory if not specified in `varexpr`. Can be a
  single parameter reference, a single parameter array with parameters defined
  in the same call of [`@infinite_parameter`](@ref),
  or a tuple where each element is either of the first two options listed.
- `base_name`: Sets the name prefix used to generate variable names. It
  corresponds to the variable name for scalar variable, otherwise, the
  variable names are set to `base_name[...]` for each index `...` of the axes
  `axes`. Furthermore, the parameter reference tuple is appended on the end of
  the name i.e., `base_name(params...)` or `base_name[...](params...)`.
- `lower_bound`: Sets the value of the variable lower bound.
- `upper_bound`: Sets the value of the variable upper bound.
- `start`: Sets the variable starting value used as initial guess in optimization.
           This can be a single value enforced over the entire infinite variable
           domain or it can be a function that maps a support value to a scalar
           guess value. Note that the function arguments must match the format
           of `parameter_refs`.
- `binary`: Sets whether the variable is binary or not.
- `integer`: Sets whether the variable is integer or not.
- `container`: Specify the container type.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP, Distributions; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 1])
t

julia> @infinite_parameter(model, w[1:2] in Normal())
2-element Array{GeneralVariableRef,1}:
 w[1]
 w[2]

julia> @infinite_variable(model, x(t, w) >= 0)
x(t, w)

julia> x = @infinite_variable(model, parameter_refs = (t, w), base_name = "x",
                              lower_bound = 0)
x(t, w)

julia> lb = [0, 1]; ub = [10, 12];

julia> @infinite_variable(model, lb[i] <= y[i = 1:2](t) <= ub[i], Int)
2-element Array{GeneralVariableRef,1}:
 y[1](t)
 y[2](t)
```
"""
macro infinite_variable(model, args...)
    _error(str...) = _macro_error(:infinite_variable, (model, args...),
                                  __source__, str...)

    extra, kw_args, requestedcontainer = _extract_kw_args(args)
    param_kw_args = filter(kw -> kw.args[1] == :parameter_refs, kw_args)

    # Check for easy case if it is anonymous single variable
    if length(extra) == 0
        code = quote
            @assert isa($model, InfiniteModel) "Model must be an `InfiniteModel`."
            JuMP.@variable($model, ($(args...)), variable_type = Infinite,
                           macro_error = $_error)
        end
    else
        x = popfirst!(extra)

        # There are several cases to consider:
        # x                                                     | type of x | x.head
        # ------------------------------------------------------+-----------+------------
        # var                                                   | Symbol    | NA
        # var[1:2]                                              | Expr      | :ref
        # var(x, y)                                             | Expr      | :call
        # var[1:2](x, y)                                        | Expr      | :call
        # var <= ub or var[1:2] <= ub                           | Expr      | :call
        # var(x, y) <= ub or var[1:2](x, y) <= ub               | Expr      | :call
        # lb <= var <= ub or lb <= var[1:2] <= ub               | Expr      | :comparison
        # lb <= var(x, y) <= ub or lb <= var[1:2](x, y) <= ub   | Expr      | :comparison
        if isexpr(x, :comparison) || isexpr(x, :call)
            inf_expr, params = InfiniteOpt._parse_parameters(_error, Val(x.head),
                                                             x.args)
        else
            inf_expr = x
            params = nothing
        end

        # check for double specification of parameters
        if length(param_kw_args) != 0 && params != nothing
            _error("Cannot specify double specify the infinite parameter " *
                   "references.")
        end

        # easy case where we can don't need to parse extra args
        if length(args) == 1
            code = quote
                @assert isa($model, InfiniteModel) "Model must be an " *
                                                   "`InfiniteModel`."
                JuMP.@variable($model, ($(inf_expr)),
                               variable_type = Infinite,
                               parameter_refs = $params,
                               macro_error = $_error)
            end
        # here we need to parse the extra args and include them in the call
        else
            rest_args = [args[i] for i = 2:length(args)]
            if isa(params, Nothing)
                code = quote
                    @assert isa($model, InfiniteModel) "Model must be an " *
                                                       "`InfiniteModel`."
                    JuMP.@variable($model, ($(inf_expr)), ($(rest_args...)),
                                   variable_type = Infinite,
                                   macro_error = $_error)
                end
            else
                code = quote
                    @assert isa($model, InfiniteModel) "Model must be an " *
                                                       "`InfiniteModel`."
                    JuMP.@variable($model, ($(inf_expr)), ($(rest_args...)),
                                   variable_type = Infinite,
                                   parameter_refs = $params,
                                   macro_error = $_error)
                end
            end
        end
    end
    return esc(code)
end

"""
    @point_variable(model::InfiniteModel, kw_args...)::GeneralVariableRef

Add an *anonymous* point variable to the model `model` described by the
keyword arguments `kw_args` and returns the variable reference. Note that the
`infinite_variable_ref` and `parameter_values` keywords are required in this
case.

```julia
@point_variable(model::InfiniteModel, infvarexpr, varexpr, args...,
                kw_args...)::GeneralVariableRef
```

Add a point variable to `model` described by the expression `varexpr`, the
positional arguments `args`, and the keyword arguments `kw_args` and the
infinite variable expr `infvarexpr`. The expression `infvarexpr` specifies the
infinite variable this point variable corresponds to and the values at which the
parameters are evaluated and must be of the form: `infvar(param_values...)`
where the parameter values `param_values...` are listed in the same format as
they are in the definition of `infvar`. The expression `varexpr` is used to
define variable specific bounds and whose name is used as an alias for the point
variable which is simply the infinite variable evaluated at the values indicated.
The expression `varexpr` can either be (note that in the following the symbol
`<=` can be used instead of `≤` and the symbol `>=`can be used instead of `≥`)
of the form:

- `varexpr` creating variables described by `varexpr`
- `varexpr ≤ ub` (resp. `varexpr ≥ lb`) creating variables described by
  `varexpr` with upper bounds given by `ub` (resp. lower bounds given by `lb`)
- `varexpr == value` creating variables described by `varexpr` with fixed values
   given by `value`
- `lb ≤ varexpr ≤ ub` or `ub ≥ varexpr ≥ lb` creating variables described by
  `varexpr` with lower bounds given by `lb` and upper bounds given by `ub`

Note that by default a point variable inherits all of the same properties as
the infinite variable it corresponds to, but that these can be overwritten
by specifying properties such as lower bounds, fix values, etc.

The expression `varexpr` can be of the form:

- `varname` creating a scalar real variable of alias name `varname`
- `varname[...]` or `[...]` creating a container of variables.

The recognized positional arguments in `args` are the following:

- `Bin`: Sets the variable to be binary, i.e. either 0 or 1.
- `Int`: Sets the variable to be integer, i.e. one of ..., -2, -1, 0, 1, 2, ...

The recognized keyword arguments in `kw_args` are the following:

- `infinite_variable_ref`: Sets the infinite variable reference that the point
  variable is associated with.
- `parameter_values`: Sets the values of the infinite parameters of the infinite
  variable at which this poitn variable is evaluated at. MUST be of the SAME
  FORMAT of that specified for the parameters in the definition of the infinite
  variable.
- `base_name`: Sets the name prefix used to generate variable names. It
  corresponds to the variable name for scalar variable, otherwise, the
  variable names are set to `base_name[...]` for each index `...` of the axes
  `axes`. This serves as the alias for `infvarexpr` (the infinite variable
  evaluated at particular parameter values).
- `lower_bound`: Sets the value of the variable lower bound.
- `upper_bound`: Sets the value of the variable upper bound.
- `start`: Sets the variable starting value used as initial guess in optimization.
- `binary`: Sets whether the variable is binary or not.
- `integer`: Sets whether the variable is integer or not.
- `container`: Specify the container type.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP, Distributions; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 1])
t

julia> @infinite_parameter(model, w[1:2] in Normal())
2-element Array{GeneralVariableRef,1}:
 w[1]
 w[2]

julia> @infinite_variable(model, x(t, w) >= 0)
x(t, w)

julia> @point_variable(model, x(0, [0, 0]), x0 <= 1)
x0

julia> x0 = @point_variable(model, x(0, [0, 0]), upper_bound = 1, base_name = "x0")
x0

julia> x0 = @point_variable(model, upper_bound = 1, base_name = "x0",
                            infinite_variable_ref = x, parameter_values = (0, [0, 0]))
x0

julia> @point_variable(model, x([0, 1][i], [0, 0]), xf[i = 1:2])
2-element Array{GeneralVariableRef,1}:
 xf[1]
 xf[2]

julia> lb = [0, 1]; ub = [10, 12];

julia> @infinite_variable(model, lb[i] <= y[i = 1:2](t) <= ub[i], Int)
2-element Array{GeneralVariableRef,1}:
 y[1](t)
 y[2](t)

julia> @point_variable(model, y[i](0), y0[i = 1:2], Bin)
2-element Array{GeneralVariableRef,1}:
 y0[1]
 y0[2]

julia> y0 = @point_variable(model, [i = 1:2], binary = true, base_name = "y0",
                             infinite_variable_ref = y[i], parameter_values = 0)
2-element Array{GeneralVariableRef,1}:
 y0[1]
 y0[2]
```
"""
macro point_variable(model, args...)
    _error(str...) = _macro_error(:point_variable, (model, args...), 
                                  __source__, str...)

    extra, kw_args, requestedcontainer = _extract_kw_args(args)
    param_kw_args = filter(kw -> kw.args[1] == :infinite_variable_ref ||
                           kw.args[1] == :parameter_values, kw_args)

    # Check for easy case if it is anonymous single variable
    if length(extra) == 0
        code = quote
            @assert isa($model, InfiniteModel) "Model must be an " *
                                               "`InfiniteModel`."
            JuMP.@variable($model, ($(args...)), variable_type = Point,
                           macro_error = $_error)
        end
    else
        x = popfirst!(extra)

        if isexpr(x, :call)
            if length(param_kw_args) != 0
                _error("Cannot double specify the infinite variable reference " *
                       "and/or its parameter values.")
            elseif x.args[1] in [:in, :<=, :>=, :(==), :≥, :≤, ∈]
                _error("Invalid input syntax.")
            end
            rest_args = [args[i] for i = 2:length(args)]
            inf_var = x.args[1]
            param_vals = Expr(:tuple, x.args[2:end]...)
            code = quote
                @assert isa($model, InfiniteModel) "Model must be an " *
                                                   "`InfiniteModel`."
                JuMP.@variable($model, ($(rest_args...)), variable_type = Point,
                               infinite_variable_ref = $inf_var,
                               parameter_values = $param_vals,
                               macro_error = $_error)
            end
        elseif (isexpr(x, :vect) || isexpr(x, :vcat)) && length(extra) == 0
            code = quote
                @assert isa($model, InfiniteModel) "Model must be an " *
                                                   "`InfiniteModel`."
                JuMP.@variable($model, ($(args...)), variable_type = Point,
                               macro_error = $_error)
            end
        else
            _error("Invalid input syntax.")
        end
    end
    return esc(code)
end

"""
    @hold_variable(model::InfiniteModel, kw_args...)::GeneralVariableRef

Add an *anonymous* hold variable to the model `model` described by the
keyword arguments `kw_args` and returns the variable reference.

```julia
@hold_variable(model::InfiniteModel, varexpr, args...,
               kw_args...)::GeneralVariableRef
```

Add a hold variable to `model` described by the expression `varexpr`, the
positional arguments `args` and the keyword arguments `kw_args`. The expression
`varexpr` can either be (note that in the following the symbol `<=` can be used
instead of `≤` and the symbol `>=`can be used instead of `≥`) of the form:

- `varexpr` creating variables described by `varexpr`
- `varexpr ≤ ub` (resp. `varexpr ≥ lb`) creating variables described by
  `varexpr` with upper bounds given by `ub` (resp. lower bounds given by `lb`)
- `varexpr == value` creating variables described by `varexpr` with fixed values
   given by `value`
- `lb ≤ varexpr ≤ ub` or `ub ≥ varexpr ≥ lb` creating variables described by
  `varexpr` with lower bounds given by `lb` and upper bounds given by `ub`

The expression `varexpr` can be of the form:

- `varname` creating a scalar real variable of name `varname`
- `varname[...]` or `[...]` creating a container of variables.

The recognized positional arguments in `args` are the following:

- `Bin`: Sets the variable to be binary, i.e. either 0 or 1.
- `Int`: Sets the variable to be integer, i.e. one of ..., -2, -1, 0, 1, 2, ...

Specifiying a hold variable which applies only to sub-domain of the model's
infinite parameter(s) domain can be done via the `parameter_bounds` keyword
argument. It is specified as a tuple of parameter bound expressions which can
be of the form:

- `(param in [lb, ub], ...)` enforcing `param` to be in a sub-domain from `lb`
                             to `ub` (note `∈` can be used in place of `in`)
- `(params in [lb, ub], ...)` enforcing that all parameter references in `params`
                              each be a in sub-domain from `lb` to `ub`
- `(lb <= param <= ub, ...)` enforcing `param` to be in a sub-domain from `lb`
                             to `ub`
- `(lb <= params <= ub, ...)` enforcing that all parameter references in `params`
                              each be a in sub-domain from `lb` to `ub`
- `(param == value, ...)` enforcing `param` to be equal to `value`
- `(params == value, ...)` enforcing that all parameter references in `params`
                            each to be equal to `value`
- Any combination of the above forms. Must be inside parentheses and comma
  separated.

Please note that when specifying value conditions on dependent infinite parameters,
a value must be provided for each parameter in the dependent container otherwise
an error will be thrown.

The other recognized keyword arguments in `kw_args` are the following:

- `base_name`: Sets the name prefix used to generate variable names. It
  corresponds to the variable name for scalar variable, otherwise, the
  variable names are set to `base_name[...]` for each index `...` of the axes
  `axes`.
- `lower_bound`: Sets the value of the variable lower bound.
- `upper_bound`: Sets the value of the variable upper bound.
- `start`: Sets the variable starting value used as initial guess in optimization.
- `binary`: Sets whether the variable is binary or not.
- `integer`: Sets whether the variable is integer or not.
- `container`: Specify the container type.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @infinite_parameter(model, t in [0, 10]))
julia> @hold_variable(model, x)
x

julia> @hold_variable(model, 0 <= y <= 4, Bin)
y

julia> y = @hold_variable(model, lower_bound = 0, upper_bound = 4,
                            binary = true, base_name = "y")
y

julia> @hold_variable(model, z[2:3] == 0)
1-dimensional DenseAxisArray{GeneralVariableRef,1,...} with index sets:
    Dimension 1, 2:3
And data, a 2-element Array{GeneralVariableRef,1}:
 z[2]
 z[3]

julia> @hold_variable(model, d, parameter_bounds = (t in [0, 5]))
d
```
"""
macro hold_variable(model, args...)
    _error(str...) = _macro_error(:hold_variable, (model, args...),
                                  __source__, str...)
    # parse the arguments
    extra, kw_args, requestedcontainer = _extract_kw_args(args)
    bound_kw_args = filter(kw -> kw.args[1] == :parameter_bounds, kw_args)

    # no bounds given so we don't need to do anything
    if length(bound_kw_args) == 0
        code = quote
            @assert isa($model, InfiniteModel) "Model must be an " *
                                               "`InfiniteModel`."
            JuMP.@variable($model, ($(args...)), variable_type = Hold,
                           macro_error = $_error)
        end
    else
        x = bound_kw_args[1].args[2]
        if isexpr(x, :call) || isexpr(x, :tuple) || isexpr(x, :comparison)
           name_expr, bounds = InfiniteOpt._extract_bounds(_error, x.args,
                                                           Val(x.head))
        else
           _error("Unrecognized input format for parameter bounds. Must be " *
                  "tuple with elements of form: par(s) in [lb, ub] or " *
                  "par(s) == value.")
        end
        extra_kw_args = filter(kw -> kw.args[1] != :parameter_bounds, kw_args)
        code = quote
            @assert isa($model, InfiniteModel) "Model must be an " *
                                               "`InfiniteModel`."
            JuMP.@variable($model, ($(extra...)), variable_type = Hold,
                           parameter_bounds = ($(bounds)), macro_error = $_error,
                           container = ($(requestedcontainer)),
                           ($(extra_kw_args...)))
        end
    end
    return esc(code)
end


## Parse derivative numerators and denominators 
# Normal 
function _parse_derivative_variable(_error, ::Union{Val{:d}, Val{:∂}}, var)
    return var
end

# Fallback 
function _parse_derivative_variable(_error, operator, var)
    _error("Unrecognized derivative syntax, use syntax `d(vref)/d(pref)` to " *
           "express the derivative.")
end

## Parse the derivative expressions ::Union{Val{:d}, Val{:∂}}
# Normal 
function _parse_derivative_expr(_error, ::Val{:call}, operator, var)
    return _parse_derivative_variable(_error, Val(operator), var)
end

# Fallback
function _parse_derivative_expr(_error, args...)
    _error("Unrecognized derivative syntax, use syntax `d(vref)/d(pref)` to " *
           "express the derivative. Only one argument variable and one operator " * 
           "parameter can be used. See `@deriv` to specify more complex derivatives.")
end

"""
    @derivative_variable(model::InfiniteModel, kw_args...)::GeneralVariableRef

Add an *anonymous* derivative to the model `model` described by the
keyword arguments `kw_args` and returns the variable reference. Note that the
`argument` and `operator_parameter` keywords are required in this
case.

```julia
@derivative_variable(model::InfiniteModel, deriv_expr, var_expr,
                     kw_args...)::GeneralVariableRef
```

Add a derivative to `model` described by the expression `var_expr`, the keyword 
arguments `kw_args`, and the derivative expr `deriv_expr`. The expression 
`deriv_expr` specifies the derivative argument and operator parameter and must be 
of the from: `d(arg_vref)/d(pref)` where `arg_vref` is a variable/derivative/measure 
with an infinite dependence on the infinite parameter `pref`. Equivalently, the 
derivative can be expressed `∂(arg_vref)/∂(pref)`. The expression `var_expr` is 
used to define variable specific bounds and whose name is used as an alias for the 
derivative reference. The expression `var_expr` can either be (note that in the 
following the symbol `<=` can be used instead of `≤` and the symbol `>=`can be 
used instead of `≥`) of the form:

- `var_expr` creating variables described by `varexpr`
- `var_expr ≤ ub` (resp. `varexpr ≥ lb`) creating variables described by
  `var_expr` with upper bounds given by `ub` (resp. lower bounds given by `lb`)
- `var_expr == value` creating variables described by `var_expr` with fixed values
   given by `value`
- `lb ≤ var_expr ≤ ub` or `ub ≥ var_expr ≥ lb` creating variables described by
  `var_expr` with lower bounds given by `lb` and upper bounds given by `ub`

Note that the preferred way to define derivatives is via [`@deriv`](@ref) which 
provides a more succinct way to specify more complex derivatives. However, this 
variable based syntax is provided as a convenient way to specify starting 
values/functions when needed.

The expression `var_expr` can be of the form:

- `varname` creating a scalar real variable of alias name `varname`
- `varname[...]` or `[...]` creating a container of variables.

The recognized keyword arguments in `kw_args` are the following:

- `argument`: Sets the argument of the differential operator.
- `operator_parameter`: Sets the infinite parameter the derivative is with respect to.
- `base_name`: Sets the name prefix used to generate variable names. It
  corresponds to the variable name for scalar variable, otherwise, the
  variable names are set to `base_name[...]` for each index `...` of the axes
  `axes`.
- `lower_bound`: Sets the value of the variable lower bound.
- `upper_bound`: Sets the value of the variable upper bound.
- `start`: Sets the derivative starting value used as initial guess in optimization.
           This can be a single value enforced over the entire infinite
           domain or it can be a function that maps a support value to a scalar
           guess value. Note that the function arguments must match the format
           of `parameter_refs(argument)`.
- `container`: Specify the container type.

**Examples**
```julia-repl
julia> @infinite_parameter(model, t in [0, 10])
t

julia> @infinite_variable(model, x(t) >= 0)
x(t)

julia> @infinite_variable(model, y[1:2](t))
2-element Array{GeneralVariableRef,1}:
 y[1](t)
 y[2](t)

julia> @derivative_variable(model, d(x)/d(t), dx <= 1, start = 0)
dx

julia> dx = @derivative_variable(model, d(x)/d(t), upper_bound = 1, base_name = "dx")
dx

julia> dx = @derivative_variable(model, upper_bound = 1, base_name = "dx",
                                  argument = x, operator_parameter = t)
dx

julia> @derivative_variable(model, d(y[i])/d(t), dx2[i = 1:2])
2-element Array{GeneralVariableRef,1}:
 dx2[1]
 dx2[2]

julia> dx = @derivative_variable(model, d(y[i])/d(t), [i = 1:2])
2-element Array{GeneralVariableRef,1}:
 ∂/∂t[y[1](t)]
 ∂/∂t[y[2](t)]
 
julia> dx = @derivative_variable(model, [i = 1:2], argument = y[i], 
                                 operator_parameter = t)
2-element Array{GeneralVariableRef,1}:
 ∂/∂t[y[1](t)]
 ∂/∂t[y[2](t)]
```
"""
macro derivative_variable(model, args...)
    _error(str...) = _macro_error(:derivative_variable, (model, args...), 
                                  __source__, str...)

    extra, kw_args, requestedcontainer = _extract_kw_args(args)
    deriv_kw_args = filter(kw -> kw.args[1] == :argument ||
                           kw.args[1] == :operator_parameter, kw_args)

    # Check for easy case if it is anonymous single variable
    if length(extra) == 0
        code = quote
            @assert isa($model, InfiniteModel) "Model must be an " *
                                               "`InfiniteModel`."
            JuMP.@variable($model, ($(args...)), variable_type = Deriv,
                           macro_error = $_error)
        end
    else
        x = popfirst!(extra)

        if isexpr(x, :call)
            if length(deriv_kw_args) != 0
                _error("Cannot double specify the argument variable reference " *
                       "and/or the operator parameter.")
            elseif x.args[1] != :/
                _error("Invalid input syntax.")
            end
            rest_args = [args[i] for i = 2:length(args)]
            vref = _parse_derivative_expr(_error, Val(x.args[2].head), x.args[2].args...)
            pref = _parse_derivative_expr(_error, Val(x.args[3].head), x.args[3].args...)
            code = quote
                @assert isa($model, InfiniteModel) "Model must be an " *
                                                   "`InfiniteModel`."
                JuMP.@variable($model, ($(rest_args...)), variable_type = Deriv,
                               argument = $vref,
                               operator_parameter = $pref,
                               macro_error = $_error)
            end
        elseif (isexpr(x, :vect) || isexpr(x, :vcat)) && length(extra) == 0
            code = quote
                @assert isa($model, InfiniteModel) "Model must be an " *
                                                   "`InfiniteModel`."
                JuMP.@variable($model, ($(args...)), variable_type = Deriv,
                               macro_error = $_error)
            end
        else
            _error("Invalid input syntax.")
        end
    end
    return esc(code)
end

## Helper function for parsing the parameter bounds and the name expression
# Check that name expression is in acceptable form or throw error
function _parse_name_expression(_error::Function, expr)
    if isexpr(expr, :ref) || isexpr(expr, :vect)|| isa(expr, Symbol) || isexpr(expr, :vcat)
        return expr
    else
        _error("Unrecognized input format for name expression. Must be of " *
               "form name[i = ..., ...](param_bounds).")
    end
end

# Return IntervalSet call given a :vect expression or error
function _make_interval_set(_error::Function, expr::Expr)
    if isexpr(expr, :vect) && length(expr.args) == 2
        return Expr(:call, :IntervalSet, expr.args...)
    else
        _error("Unrecognized input format for parameter bounds. Must be of form " *
        "par in [lb, ub], lb <= par <= ub,  or par == value.")
    end
end

## Return a bound pair of form param => IntervalSet(lb, ub) or error
# Call expressions using :in
function _make_bound_pair(_error::Function, expr::Expr,
                          ::Union{Val{:in}, Val{:∈}})
    set = _make_interval_set(_error, expr.args[3])
    param = expr.args[2]
    return Expr(:call, :(=>), param, set)
end

# Call expressions using :(==)
function _make_bound_pair(_error::Function, expr::Expr, ::Val{:(==)})
    set = _make_interval_set(_error, Expr(:vect, expr.args[3], expr.args[3]))
    param = expr.args[2]
    return Expr(:call, :(=>), param, set)
end

# Comparison expressions using something else
function _make_bound_pair(_error::Function, expr::Expr, first)
    _error("Invalid set format operators. Must be of form par in [lb, ub], " *
           "lb <= par <= ub, or par == value.")
end

# Comparison expressions using :(<=)
function _make_bound_pair(_error::Function, expr::Expr, ::Val{:(<=)},
                          ::Val{:(<=)})
    set = _make_interval_set(_error, Expr(:vect, expr.args[1], expr.args[5]))
    param = expr.args[3]
    return Expr(:call, :(=>), param, set)
end

# Comparison expressions using :(>=)
function _make_bound_pair(_error::Function, expr::Expr, ::Val{:(>=)},
                          ::Val{:(>=)})
    set = _make_interval_set(_error, Expr(:vect, expr.args[5], expr.args[1]))
    param = expr.args[3]
    return Expr(:call, :(=>), param, set)
end

# Comparison expressions using something else
function _make_bound_pair(_error::Function, expr::Expr, first, second)
    _error("Invalid set format operators. Must be of form par in [lb, ub], " *
           "lb <= par <= ub, or par == value.")
end

# General wrapper
function _make_bound_pair(_error::Function, expr::Expr)
    if isexpr(expr, :call)
        return _make_bound_pair(_error, expr, Val(expr.args[1]))
    elseif isexpr(expr, :comparison)
        return _make_bound_pair(_error, expr, Val(expr.args[2]), Val(expr.args[4]))
    else
        _error("Unrecognized input format for parameter bounds. Must be of form " *
               "par in [lb, ub], lb <= par <= ub, or par == value.")
    end
end

# Return a dictionary of parameter bounds given raw vector of call expressions
function _parse_parameter_bounds(_error::Function, args::Vector)
    dict_pairs = Tuple(_make_bound_pair(_error, arg) for arg in args)
    return Expr(:call, :ParameterBounds, Expr(:tuple, dict_pairs...))
end

# Only 1 parameter bound is given thus dispatch as a vector to make dictionary
function _parse_parameter_bounds(_error::Function, expr::Expr)
    return _parse_parameter_bounds(_error, [expr])
end

## Return name expression and parameter dictionary expression separatedly
# (:call) In this case we are not sure if a name expression is given
function _extract_bounds(_error::Function, args::Vector, ::Val{:call})
    # check if only one parameter bound was given and nothing else
    if args[1] in [:in, :∈, :(==)]
        bounds = _parse_parameter_bounds(_error, Expr(:call, args...))
        return nothing, bounds
    # otherwise parameter bounds were given with a name expression
    else
        name_expr = _parse_name_expression(_error, args[1])
        bounds = _parse_parameter_bounds(_error, args[2:end])
        return name_expr, bounds
    end
end

# (:tuple) In this case we know mulitple bounds are given with no name expression
function _extract_bounds(_error::Function, args::Vector, ::Val{:tuple})
    bounds = _parse_parameter_bounds(_error, args)
    return nothing, bounds
end

# (:comparison) In this case we have a single interval set and nothing else
function _extract_bounds(_error::Function, args::Vector, ::Val{:comparison})
    bounds = _parse_parameter_bounds(_error, Expr(:comparison, args...))
    return nothing, bounds
end

"""
    @BDconstraint(model::InfiniteModel, [i = ..., ...](bound_expr), constr_expr;
                  [kw_args...])::InfOptConstraintRef

Add an anonymous bounded constraint to `model` and return an appropriate
container of constraint reference(s).

```julia
    @BDconstraint(model::InfiniteModel, name[i = ..., ...](bound_expr),
                  constr_expr; [kw_args...])::InfOptConstraintRef
```

Add a named bounded constraint to `model` and return an appropriate
container of constraint reference(s). This defines the constraint as expressed
in `constr_expr` over some sub-domain of parameters as indicated by `bound_expr`.
The format of `constr_expr` must follow the same syntax as that specified in
[`JuMP.@constraint`](@ref). For example, if we want to express the constraint
`2T(t, x) + 3y = 42`, the constraint expression `constr_expr` would be
`2 * T + 3 * y == 42`.

By default, `JuMP.@constraint` would express the above example constraint over
the whole domain of `t` and `x`. However, we can use `@BDconstraint` to express
this constraint over some sub-domain(s) via `bound_expr`. Here `(bound_expr)`
can be of the form:

- `(param in [lb, ub], ...)` enforcing `param` to be in a sub-domain from `lb`
                             to `ub` (note `∈` can be used in place of `in`)
- `(params in [lb, ub], ...)` enforcing that all parameter references in `params`
                              each be a in sub-domain from `lb` to `ub`
- `(lb <= param <= ub, ...)` enforcing `param` to be in a sub-domain from `lb`
                             to `ub`
- `(lb <= params <= ub, ...)` enforcing that all parameter references in `params`
                              each be a in sub-domain from `lb` to `ub`
- `(param == value, ...)` enforcing `param` to be equal to `value`
- `(params == value, ...)` enforcing that all parameter references in `params`
                            each to be equal to `value`
- Any combination of the above forms. Must be inside parentheses and comma
  separated.

Please note that when specifying value conditions on dependent infinite parameters,
a value must be provided for each parameter in the dependent container otherwise
an error will be thrown.

Like typical constraints, the `container` keyword argument can be used to specify
the `JuMP` container type used to store the constraint references. Note this
macro errors if `bound_expr` is ommited or if some unrecognized syntax is used.

**Examples**
```julia-repl
julia> @BDconstraint(model, c1(t in [0, 1]), T^2 + z <= 1)
c1 : T(x, t)² + z ≤ 1.0, ∀ t ∈ [0, 1], x[1] ∈ [-1, 1], x[2] ∈ [-1, 1], x[3] ∈ [-1, 1],

julia> @BDconstraint(model, c2[i = 1:3](x[i] in [0, 1]), T^2 + z + x[i] <= 1)
3-element Array{InfOptConstraintRef,1}:
 c2[1] : T(x, t)² + z + x[1] ≤ 1.0, ∀ t ∈ [0, 1], x[1] ∈ [0, 1], x[2] ∈ [-1, 1], x[3] ∈ [-1, 1]
 c2[2] : T(x, t)² + z + x[2] ≤ 1.0, ∀ t ∈ [0, 1], x[1] ∈ [-1, 1], x[2] ∈ [0, 1], x[3] ∈ [-1, 1]
 c2[3] : T(x, t)² + z + x[3] ≤ 1.0, ∀ t ∈ [0, 1], x[1] ∈ [-1, 1], x[2] ∈ [-1, 1], x[3] ∈ [0, 1]

julia> @BDconstraint(model, (x == 0, t == 0), T^2 + z <= 1)
T(x, t)² + z ≤ 1.0, ∀ t = 0, x[1] = 0, x[2] = 0, x[3] = 0

julia> @BDconstraint(model, [i = 1:3](x[i] == 0), T^2 + z <= 1,
                     container = SparseAxisArray)
JuMP.Containers.SparseAxisArray{InfOptConstraintRef,1,Tuple{Any}} with 3 entries:
  [3]  =  T(x, t)² + z ≤ 1.0, ∀ t ∈ [0, 1], x[1] = 0, x[2] ∈ [-1, 1], x[3] ∈ [-1, 1]
  [2]  =  T(x, t)² + z ≤ 1.0, ∀ t ∈ [0, 1], x[1] ∈ [-1, 1], x[2] = 0, x[3] ∈ [-1, 1]
  [1]  =  T(x, t)² + z ≤ 1.0, ∀ t ∈ [0, 1], x[1] ∈ [-1, 1], x[2] ∈ [-1, 1], x[3] = 0
```
"""
macro BDconstraint(model, args...)
    # define appropriate error message function
    _error(str...) = _macro_error(:BDconstraint, (model, args...), 
                                  __source__, str...)

    # parse the arguments
    extra, kw_args, requestedcontainer = _extract_kw_args(args)
    bound_kw_args = filter(kw -> kw.args[1] == :parameter_bounds, kw_args)

    # check for double specification of parameter bounds
    if length(bound_kw_args) != 0
        _error("Cannot double specify the parameter bounds. Use form " *
               "@BDconstraint(model, name[i=..., ...](par in [lb, ub], " *
               "par2 = value, ...), expr).")
    end

    # check that enough arguments are given
    if length(extra) != 2
        _error("Incorrect amount of arguments. Must be of form " *
               "@BDconstraint(model, name[i=..., ...](par in [lb, ub], " *
               "par2 == value, ...), expr).")
    # otherwise we have a 3 argument form
    else
        # process the 2nd argument for the parameter bounds if provided
        x = popfirst!(extra)
        if isexpr(x, :ref) || isexpr(x, :vect) || isa(x, Symbol) || isexpr(x, :vcat)
            _error("Must specify at least one parameter bound of the form " *
                   "@BDconstraint(model, name[i=..., ...](par in [lb, ub], " *
                   "par2 == value, ...), expr).")
        elseif isexpr(x, :call) || isexpr(x, :tuple) || isexpr(x, :comparison)
            name_expr, bounds = InfiniteOpt._extract_bounds(_error, x.args,
                                                            Val(x.head))
        else
            _error("Unrecognized input format for name expression. Must be of " *
                   "form @BDconstraint(model, name[i=..., ...](par in [lb, ub], " *
                   "par2 == value, ...), expr).")
        end
        # we have a single anonymous constraint
        if isa(name_expr, Nothing)
            code = quote
                @assert isa($model, InfiniteModel) "Model must be an " *
                                                   "`InfiniteModel`."
                JuMP.@constraint($model, ($(extra[1])),
                                 parameter_bounds = ($(bounds)), ($(kw_args...)),
                                 container = ($(requestedcontainer)))
            end
        # we have some sort of name expression in our constraint
        else
            code = quote
                @assert isa($model, InfiniteModel) "Model must be an " *
                                                   "`InfiniteModel`."
                JuMP.@constraint($model, ($(name_expr)), ($(extra[1])),
                                 parameter_bounds = ($(bounds)), ($(kw_args...)),
                                 container = ($(requestedcontainer)))
            end
        end
    end
    return esc(code)
end

# TODO add looping capability for multi-dimensional refs
"""
    @set_parameter_bounds(ref, bound_expr; [force::Bool = false])::Nothing

Specify new parameter bounds for a constraint reference or hold variable
reference `ref`. These bounds correspond to bounding a constraint in an
equivalent way to using [`@BDconstraint`](@ref) or to limiting the scope of a
hold variable in an equivalent way to using the `parameter_bounds` keyword
argument in [`@hold_variable`](@ref). Here `(bound_expr)` can be of the form:

- `(param in [lb, ub], ...)` enforcing `param` to be in a sub-domain from `lb`
                             to `ub` (note `∈` can be used in place of `in`)
- `(params in [lb, ub], ...)` enforcing that all parameter references in `params`
                              each be a in sub-domain from `lb` to `ub`
- `(lb <= param <= ub, ...)` enforcing `param` to be in a sub-domain from `lb`
                             to `ub`
- `(lb <= params <= ub, ...)` enforcing that all parameter references in `params`
                              each be a in sub-domain from `lb` to `ub`
- `(param == value, ...)` enforcing `param` to be equal to `value`
- `(params == value, ...)` enforcing that all parameter references in `params`
                            each to be equal to `value`
- Any combination of the above forms. Must be inside parentheses and comma
  separated.

Please note that when specifying value conditions on dependent infinite parameters,
a value must be provided for each parameter in the dependent container otherwise
an error will be thrown.

Errors if the constraint or variable corresponding to `ref` already has bounds.
However, using `force = true` can be used ignore the current bounds and
overwrite them with new ones. Also, note that bounds on dependent constraints
of hold variables will be updated to account for changes in hold variable bounds.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10])
t

julia> @infinite_variable(model, x(t))
x(t)

julia> @hold_variable(model, y)
y

julia> @constraint(model, con, x + y == 0)
con : x(t) + y = 0.0, ∀ t ∈ [0, 10]

julia> @set_parameter_bounds(y, t in [0, 5])

julia> con
con : x(t) + y = 0.0, ∀ t ∈ [0, 5]

julia> @set_parameter_bounds(con, t == 0, force = true)

julia> con
con : x(t) + y = 0.0, ∀ t = 0
```
"""
macro set_parameter_bounds(ref, bound_expr, args...)
    # define appropriate error message function
    _error(str...) = _macro_error(:set_parameter_bounds, (ref, bound_expr, args...), 
                                  __source__, str...)
    # parse the arguments
    extra, kw_args, requestedcontainer = _extract_kw_args(args)
    extra_kw_args = filter(kw -> kw.args[1] != :force, kw_args)
    if length(extra) != 0
        _error("Too many positional arguments.")
    elseif length(extra_kw_args) != 0
        _error("Unrecognized keyword arguments.")
    end
    # parse the bounds
    x = bound_expr
    if isexpr(x, :call) || isexpr(x, :tuple) || isexpr(x, :comparison)
       name_expr, bounds = InfiniteOpt._extract_bounds(_error, x.args,
                                                       Val(x.head))
    else
       _error("Unrecognized input format for parameter bounds. Must be of " *
              "tuple with elements of form: par(s) in [lb, ub] or " *
              "par(s) == value.")
    end
    # prepare the code
    code = :(set_parameter_bounds($ref, $bounds; ($(args...)), _error = $_error))
    return esc(code)
end

"""
    @add_parameter_bounds(ref, bound_expr)::Nothing

Add new parameter bounds for a constraint reference or hold variable
reference `ref`. These bounds correspond to bounding a constraint in an
equivalent way to using [`@BDconstraint`](@ref) or to limiting the scope of a
hold variable in an equivalent way to using the `parameter_bounds` keyword
argument in [`@hold_variable`](@ref). Here `(bound_expr)` can be of the form:

- `(param in [lb, ub], ...)` enforcing `param` to be in a sub-domain from `lb`
                             to `ub` (note `∈` can be used in place of `in`)
- `(params in [lb, ub], ...)` enforcing that all parameter references in `params`
                              each be a in sub-domain from `lb` to `ub`
- `(lb <= param <= ub, ...)` enforcing `param` to be in a sub-domain from `lb`
                             to `ub`
- `(lb <= params <= ub, ...)` enforcing that all parameter references in `params`
                              each be a in sub-domain from `lb` to `ub`
- `(param == value, ...)` enforcing `param` to be equal to `value`
- `(params == value, ...)` enforcing that all parameter references in `params`
                            each to be equal to `value`
- Any combination of the above forms. Must be inside parentheses and comma
  separated.

Please note that when specifying value conditions on dependent infinite parameters,
a value must be provided for each parameter in the dependent container otherwise
an error will be thrown.

Errors if the new bounds cause irreconcilable differences with existing measures
and constraints. For example, this occurs when adding hold variable bounds
that are outside the domain of a bounded constraint that uses that hold variable.
Also, note that bounds on dependent constraints of hold variables will be
updated to account for changes in hold variable bounds.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10])
t

julia> @infinite_parameter(model, q in [-2, 2])
q

julia> @infinite_variable(model, x(t, q))
x(t, q)

julia> @hold_variable(model, y)
y

julia> @constraint(model, con, x + y == 0)
con : x(t, q) + y = 0.0, ∀ t ∈ [0, 10], q ∈ [-2, 2]

julia> @add_parameter_bounds(y, t in [0, 5])

julia> con
con : x(t, q) + y = 0.0, ∀ t ∈ [0, 5]

julia> @add_parameter_bounds(con, q == 0)

julia> con
con : x(t, q) + y = 0.0, ∀ t ∈ [0, 5], q = 0
```
"""
macro add_parameter_bounds(ref, bound_expr)
    # define appropriate error message function
    _error(str...) = _macro_error(:add_parameter_bounds, (ref, bound_expr), 
                                  __source__, str...)
    # parse the bounds
    x = bound_expr
    if isexpr(x, :call) || isexpr(x, :tuple) || isexpr(x, :comparison)
       name_expr, bounds = InfiniteOpt._extract_bounds(_error, x.args,
                                                       Val(x.head))
    else
       _error("Unrecognized input format for parameter bounds. Must be of " *
              "tuple with elements of form: par(s) in [lb, ub] or " *
              "par(s) = value.")
    end
    # prepare the code
    code = :(add_parameter_bounds($ref, $bounds, _error = $_error))
    return esc(code)
end

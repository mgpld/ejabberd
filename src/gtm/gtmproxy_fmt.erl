-module(gtmproxy_fmt).
% Created gtmproxy_fmt.erl the 02:17:02 (16/06/2014) on core
% Last Modification of gtmproxy_fmt.erl at 13:30:38 (02/02/2017) on core
%
% Author: "rolph" <rolphin@free.fr>

-export([
    args/1,
    ref/1
]).

args(Args) ->
    fmt(Args, []).

ref(Args) ->
    ref(Args, []).

fmt([], Result) ->
    list_to_binary(lists:reverse(Result));
fmt([Elem], Result) ->
    fmt([], [ [$", filter(Elem), $"] | Result ]);
fmt([Elem|Rest], Result) ->
    fmt(Rest, [ $, , [$", filter(Elem), $"] | Result ]).

ref([], Result) ->
    list_to_binary(lists:reverse(Result));
ref([Elem], Result) ->
    ref([], [ filter(Elem) | Result ]);
ref([Elem|Rest], Result) ->
    ref(Rest, [ $",$", $,, $", $", filter(Elem) | Result ]).


filter(Elem) when is_integer(Elem) ->
    integer_to_list(Elem);
filter(Elem) when is_atom(Elem) ->
    atom_to_list(Elem);
filter(Elem) ->
    Elem.

-module(hyd_pages).
% Created hyd_pages.erl the 12:15:48 (04/10/2015) on core
% Last Modification of hyd_pages.erl at 12:25:45 (04/10/2015) on core
% 
% Author: "rolph" <rolphin@free.fr>

-export([
    module/0,
    reload/0
]).

-export([
    explore/1, explore/2, explore/3, explore/4
]).

module() ->
    <<"pages">>.

reload() ->
    hyd:reload( module() ).

run(Op) ->
    case hyd:call(Op) of
        {ok, Elements } ->
            
            case lists:foldl( fun
                (_, {error, _} = _Acc) ->
                    _Acc;
                ({error, _} = _Error, _) ->
                    _Error;
                (X, Acc) ->
                    case db_results:unpack(X) of
                        {ok, Result} ->
                            [ Result | Acc ];
                        {error, _} = Error ->
                            Error
                    end
                end, [], Elements) of

                    {error, _} = Error ->
                        Error;

                    Results when is_list(Results) ->
                        lists:flatten(Results)
                end;
            
        _ ->
            internal_error(833, Op)
    end.

explore(Userid) ->
    explore(Userid, 50).

explore(Userid, Count) ->
    explore(Userid, Count, <<"up">>).

explore(Userid, Count, Way) ->
    explore(Userid, Count, Way, 0).

explore(Userid, Count, Way, From) ->
    Ops = [
        hyd:operation(<<"explore">>, module(), [ Userid, Count, Way, From ])
    ],
    run(Ops).
    
internal_error(Code) ->
    hyd:error(?MODULE, Code).

internal_error(Code, Args) ->
    hyd:error(?MODULE, Code, Args).

%%
%% Created hyp_geoip.erl the 15:02:23 (04/10/2017) on core
%% Last Modification of hyp_geoip.erl at 08:10:18 (05/10/2017) on core
%% 
%% @author ak <ak@harmonygroup.net>
%% @doc Description.
%%

-module(hyp_geoip).

-export([load/1]).

-include("ejabberd.hrl").
-include("logger.hrl").

load(File) ->
    case file:open(File, [read, binary]) of
        {ok, Fd} ->
            read_lines(Fd, File);

        {error, Reason} ->
            ?ERROR_MSG("Failed to read file: ~p\n", [ File ])
    end.

read_lines(Fd, File) ->
    {ok, Re} = re:compile(","),
    read_lines(Fd, File, Re, 0),
    file:close(Fd).

%% @doc Hard limit, 3 Million entries.
read_lines(Fd, File, Re, 3000000) ->
    ok;
read_lines(Fd, File, Re, Acc) ->
    case file:read_line(Fd) of
        {ok, Line} ->
            case re:split(Line, Re) of
                [] ->
                    read_lines(Fd, File, Re, Acc);
    
                %% @doc Skip header line.
                [<<"network">> | _ ] ->
                    read_lines(Fd, File, Re, Acc);

                [ Network, Id, Country | _ ] ->
                    io:format("Network: ~p, Country: ~p, Low/High: ~p\n", [ Network, Country, inet_cidr:parse(Network) ]),
                    store(Network, Id, Country),
                    read_lines(Fd, File, Re, Acc + 1);
                    
                Tokens ->
                    io:format("1: ~p\n", [ hd(Tokens) ]),
                    read_lines(Fd, File, Re, Acc)
            end;
        eof ->
            ok;

        {error, _} = Err ->
            ?ERROR_MSG("Failed read from lite.sql, reason: ~p", [Err]),
            Err
    end.

store(Network, _Id, Country) ->
    try inet_cidr:parse(Network) of
        {Low, High, _} ->
            LowIp = list_to_binary(inet_parse:ntoa(Low)),
            HighIp = list_to_binary(inet_parse:ntoa(High)),
            db:call(<<"store">>,<<"geoip">>, [ LowIp, HighIp, Country ])

    catch
        _:_ ->
            ok
    end.

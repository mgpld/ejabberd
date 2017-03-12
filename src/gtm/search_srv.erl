-module(search_srv).
% Created search_srv.erl the 16:38:24 (10/03/2017) on core
% Last Modification of search_srv.erl at 14:27:46 (12/03/2017) on core
% 
% Author: "ak" <ak@harmonygroup.net>

-behaviour(gen_server).

-include("logger.hrl").

-export([ 
    start/5,
    start_link/5,
    stop/0, stop/1
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-record(state, {
    state,
    seqid,
    userid,
    parent,
    motif,
    chunk,
    searchid,
    result
}).

-define(INACTIVITY_TIMEOUT, 60000).

start(Motif, ChunkSize, Userid, SeqId, Parent) ->
    gen_server:start(?MODULE, [Motif, ChunkSize, Userid, SeqId, Parent], []).

start_link(Motif, ChunkSize, Userid, SeqId, Parent) ->
    gen_server:start_link(?MODULE, [Motif, ChunkSize, Userid, SeqId, Parent], []).

stop() ->
    gen_server:cast(?MODULE, stop).

stop(Pid) ->
    gen_server:cast(Pid, stop).


% callbacks
init([Motif, ChunkSize, Userid, SeqId, Parent]) ->
    {ok, #state{
        seqid=SeqId,
        userid=Userid,
        parent=Parent,
        chunk=ChunkSize,
        motif=Motif
    }, 0};

init(_) ->
    {stop, badarg}.

handle_info({db, SeqId, Result}, #state{ state=init, parent=Parent } = State) ->
    ?DEBUG(?MODULE_STRING "[~5w] (init) got: ~p", [ ?LINE, Result ]),
    case Result of
        [<<>>] ->
            Parent ! {db, SeqId, Result},
            {stop, normal, State};

        {error, _} = Error ->
            Parent ! {db, SeqId, Result},
            {stop, normal, State};

        {ok, Data} ->
            Parent ! {db, SeqId, Data},
            case  check_response(Data, State) of
                {error, _} ->
                    {stop, normal, State};

                {ok, Response} ->
                    case proplists:get_value(<<"key">>, Response) of
                        undefined ->
                            {stop, normal, State};

                        Searchid ->
                            {noreply, State#state{state=run, searchid=Searchid}, ?INACTIVITY_TIMEOUT}
                    end
            end
    end;
handle_info({db, SeqId, Result}, #state{ state=run, parent=Parent } = State) ->
    ?DEBUG(?MODULE_STRING "[~5w] (run) got: ~p", [ ?LINE, Result ]),
    Parent ! {db, SeqId, Result},
    {noreply, State, ?INACTIVITY_TIMEOUT};

handle_info(timeout, #state{ seqid=SeqId, state=undefined, motif=Motif, userid=Userid } = State) ->
    hyd_fqids:action_async(SeqId, <<"user">>, <<"incsearch">>, [ Userid, Motif ]),
    {noreply, State#state{ state=init }};

handle_info(timeout, #state{ state=run, parent=Parent } = State) ->
    cleanup(State),
    Parent ! {stop, ?MODULE, self()},
    {noreply, State#state{ state=stop }};

handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State};

handle_info(_Info, State) ->
    ?DEBUG(?MODULE_STRING "[~5w] handle_info unhandled: ~p", [ ?LINE, _Info ]),
    {noreply, State}.

handle_cast({chunk, SeqId}, #state{ state=run, parent=Parent, result=Result } = State) ->
    Parent ! {db, SeqId, Result},
    {noreply, State};

handle_cast(stop, State) ->
    Reason = normal,
    {stop, Reason, State};

handle_cast(_Cast, State) ->
    ?DEBUG(?MODULE_STRING "[~5w] handle_cast unhandled: ~p", [ ?LINE, _Cast ]),
    {noreply, State}.

handle_call(_Call, _From, State) ->
    ?DEBUG(?MODULE_STRING "[~5w] handle_call unhandled: ~p", [ ?LINE, _Call ]),
    {reply, {error, einval}, State}.

terminate(_Reason, _State) ->
    ?DEBUG(?MODULE_STRING "[~5w] terminate: ~p", [ ?LINE, _State ]),
    ok.

code_change(_, State, _Vsn) ->
    {ok, State}.


%% internals
check_response(Response, State) ->
    case db_results:unpack(Response) of
        {ok, Infos, More} ->
            ?DEBUG(?MODULE_STRING "[~5w] handle_response DB: Infos: ~p", [ ?LINE, Infos ]),
            case db_results:unpack(More) of
                {ok, _} = Answer ->
                    ?DEBUG(?MODULE_STRING "[~5w] Async DB: Actions: ~p", [ ?LINE, Answer ]),
                    Answer;

                {error, Reason} = Error ->
                    ?DEBUG(?MODULE_STRING "[~5w] handle_response DB: Error: ~p", [ ?LINE, Error ]),
                    Error
            end;

        {error, Reason} = Error ->
            ?DEBUG(?MODULE_STRING "[~5w] DB: Error: ~p", [ ?LINE, Error ]),
            Error
        end.

cleanup(#state{ searchid=undefined }) ->
    ok;
cleanup(#state{ searchid=Searchid, userid=Userid }) ->
    case db:call(<<"clean">>, <<"incsearch">>, [ Userid, Searchid ]) of
        {ok, Result} ->
            ok;
        _Any ->
            ?DEBUG(?MODULE_STRING "[~5w] cleanup error: ~p", [ ?LINE, _Any ])
    end.
        

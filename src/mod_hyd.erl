-module(mod_hyd).
% Created mod_hyd.erl the 20:41:19 (11/07/2014) on core
% Last Modification of mod_hyd.erl at 23:00:28 (13/07/2014) on core
% 
% Author: "ako" <antoine.koener@free.fr>

-author('antoine.koener@free.fr').

-behaviour( gen_server ).
-behaviour( gen_mod ).

%% External exports
-export([
    start_link/2
]).

% gen_mod callbacks
-export([
    start/2,
    stop/1
]).


%% gen_server callbacks
-export([
    init/1,
    handle_info/2,
    handle_call/3,
    handle_cast/2,
    terminate/2,
    code_change/3]).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include("logger.hrl").

-record( state, {
    host,
    timeout
}).

-record( hyd, {
    key,
    value
}).


-ifdef(DBGFSM).
-define(FSMOPTS, [{debug, [trace]}]).
-else.
-define(FSMOPTS, []).
-endif.

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------

-define(PROCNAME, hyd).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Host, Opts) ->
    Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
    gen_server:start_link({local, Proc}, ?MODULE, [Host, Opts], []).

start(Host, Opts) ->
    %start_supervisor(Host),
    Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
    ChildSpec =
        {Proc,
         {?MODULE, start_link, [Host, Opts]},
         transient,
         1000,
         worker,
         [?MODULE]},
    supervisor:start_child(ejabberd_sup, ChildSpec).

stop(Host) ->
    %stop_supervisor(Host),
    Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
    gen_server:call(Proc, stop), 
    supervisor:delete_child(ejabberd_sup, Proc).

%%
init([ Host, Opts ]) ->

    IdentFun = fun(A) -> A end,
    Node = gen_mod:get_opt(node, Opts, IdentFun, hyd@localhost),
    Timeout = gen_mod:get_opt(node, Opts, IdentFun, 30000), 
    Cookie = gen_mod:get_opt(cookie, Opts, IdentFun, undefined), 

    mnesia:create_table(?PROCNAME,
	[{ram_copies, [node()]},
	{attributes, record_info(fields, ?PROCNAME)}]),

    mnesia:add_table_copy(?PROCNAME, node(), ram_copies),


    % Setting up the node connection
    erlang:set_cookie(Node, Cookie),

    may_write(Node),

    {ok, #state{
	host=Host,
	timeout=Timeout
    }}.


handle_call(_, _From, State) ->
    {reply, undefined, State}.

handle_cast( _, State) ->
    {noreply, State}.

handle_info( _, State ) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_, State, _Vsn) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
% start_supervisor(Host) ->
%     Proc = gen_mod:get_module_proc(Host, hyd_sup),
%     ChildSpec =
%         {Proc,
%          {ejabberd_tmp_sup, start_link,
%           [Proc, mod_muc_room]},
%          permanent,
%          infinity,
%          supervisor,
%          [ejabberd_tmp_sup]},
%     supervisor:start_child(ejabberd_sup, ChildSpec).
% 
% stop_supervisor(Host) ->
%     Proc = gen_mod:get_module_proc(Host, hyd_sup),
%     supervisor:terminate_child(ejabberd_sup, Proc),
%     supervisor:delete_child(ejabberd_sup, Proc).


% May write in mnesia which node hold the gtmproxy
% Checking the current node if any and see if it's ok (can write on it)
may_write(Node) ->
    Read = fun() ->
	mnesia:read(hyd,node)
    end,
    case mnesia:activity({transaction, 3}, Read) of
	[] ->
	    Write = fun() ->
		mnesia:write(#hyd{ 
		    key = node, 
		    value = Node})
		end,
	    mnesia:activity({transaction, 3}, Write);
	    
	[#hyd{value=Node}] ->
	    % the node is already setup
	    ?DEBUG(?MODULE_STRING " gtm node is already configured: ~p", [ Node ]),
	    ok;

	[#hyd{value=OtherNode}] ->
	    % The node from the configuration and the node set is different
	    ?WARNING_MSG(?MODULE_STRING " gtm node from configuration differs from mnesia, ignoring configuration: ~p/~p", [
		Node, OtherNode])
    end.

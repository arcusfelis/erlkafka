%%%-------------------------------------------------------------------
%%% File     : kafka_server_sup.erl
%%% Author   : Milind Parikh <milindparikh@gmail.com>
%%%-------------------------------------------------------------------


-module(kafka_server_sup).
-author("Milind Parikh <milindparikh@gmail.com> [http://www.milindparikh.com]").
-behaviour(supervisor).


-export([start_link/1, start_link/0,
	 get_ids/0,
	 get_random_broker_instance_from_pool/1
	]).
-export([init/1]).


-define(DEFAULT_POOL_COUNT, 5).


%%%-------------------------------------------------------------------
%%%                         API FUNCTIONS
%%%-------------------------------------------------------------------


start_link() -> 

   case application:get_env(erlkafka_app,enable_kafka_autodiscovery)  of 
       undefined -> 
       	          start_link([{0, '127.0.0.1', 9092}]);
       {ok, false} -> 
              case application:get_env(erlkafka_app,kafka_brokers) of 
                   undefined ->
                           % This is default and if it does not work, 
         		   % change the application env

      	                   start_link([{0, '127.0.0.1', 9092}]);
                   {ok, Brokers} -> 
                           start_link(Brokers)
              end;
       {ok,true}  -> 
              start_link(kafka_protocol:get_dynamic_list_of_brokers())
    end.

        
	 


start_link(Params) ->

    supervisor:start_link({local, ?MODULE},
			  ?MODULE, [Params]).


get_random_broker_instance_from_pool(Broker) when is_integer(Broker) -> 
    BrokerPoolCount = param("BrokerPoolCount", ?DEFAULT_POOL_COUNT),	
    Pids = get_ids(),
    BrokerInstance = Broker*BrokerPoolCount + random:uniform(BrokerPoolCount),
     
    lists:nth(1, 
        lists:filter(fun ({_Child, Id} ) -> 
        		     case Id =:=  BrokerInstance
                               of true -> true; 
	            		  false-> false  
		             end 
		     end,
		     Pids));
get_random_broker_instance_from_pool(Broker) when is_pid(Broker) -> 
    {Broker, 0}.




get_ids() ->
    [{Child, Id} ||
	{Id, Child, _Type, _Modules} <- supervisor:which_children(?MODULE),
	Child /= undefined, Id /= 0].



%%%-------------------------------------------------------------------
%%%                         SUPERVISOR CB FUNCTIONS
%%%-------------------------------------------------------------------




init([Params]) -> 
  BrokerPoolCount = param(broker_pool_count, ?DEFAULT_POOL_COUNT),
  RestartStrategy = {one_for_one, 0, 1},
  Children = 
   lists:flatten(
    lists:map( fun ({Broker, Host, Port}) -> 
                      lists:map(fun (X) -> {Broker*BrokerPoolCount + X, 
                                              {kafka_server, start_link, [[Host, Port]]},
					      transient,
					      brutal_kill,
					      worker,
					      [kafka_server]
                                           } 
                                end, 
                                lists:seq(1, BrokerPoolCount))
		   end, 
		   Params)
 ),


  {ok, {RestartStrategy, Children}}.



%%%-------------------------------------------------------------------
%%%                         INTERNAL  FUNCTIONS
%%%-------------------------------------------------------------------

param(Name, Default)->
	case application:get_env(erlkafka_app, Name) of
		{ok, Value} -> Value;
		_-> Default
	end.



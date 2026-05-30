--!strict
--[[
    FileName    > Types.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 30/05/2026
--]]

export type State = {
	Name: string,
	Parent: State?,
	Children: { [string]: State },
	_OnEnter: ((state: State, context: any) -> ())?,
	_OnExit: ((state: State, context: any) -> ())?,
	_OnUpdate: ((state: State, dt: number, context: any) -> ())?,
	_ChildKey: string?,

	SetName: (self: State, name: string) -> boolean,
	Enter: (self: State, context: any?) -> (),
	Exit: (self: State, context: any?) -> (),
	Update: (self: State, dt: number, context: any?) -> (),
	_SetParent: (self: State, parent: State?) -> boolean,
}

export type StateHandlers<Context> = {
	Enter: ((state: State, context: Context) -> ())?,
	Exit: ((state: State, context: Context) -> ())?,
	Update: ((state: State, dt: number, context: Context) -> ())?,
}

export type Machine = {
	_Id: string?,
	_ClientAuthoritative: boolean,
	Transitioned: any,
	Destroyed: any,
	_States: { [string]: State },
	_Initial: State?,
	_Current: State?,
	_Running: boolean,
	_IsTransitioning: boolean,
	_PendingTransitions: { any },
	_PendingTransitionHead: number,
	_PendingTransitionTail: number,
	_PendingTransitionDrainScheduled: boolean,
	_Destroyed: boolean,

	AddState: (self: Machine, state: State, parent: State?) -> boolean,
	GetState: (self: Machine, name: string) -> State?,
	GetId: (self: Machine) -> string?,
	SetId: (self: Machine, id: string) -> boolean,
	IsClientAuthoritative: (self: Machine) -> boolean,
	SetClientAuthoritative: (self: Machine, is_client_authoritative: boolean) -> boolean,
	SetInitial: (self: Machine, state: State) -> boolean,
	GetCurrent: (self: Machine) -> State?,
	IsRunning: (self: Machine) -> boolean,
	Start: (self: Machine, context: any?, source: Player?) -> boolean,
	Stop: (self: Machine, context: any?, source: Player?) -> boolean,
	Transition: (self: Machine, target: State, context: any?, source: Player?) -> boolean,
	Update: (self: Machine, dt: number, context: any?) -> (),
	Destroy: (self: Machine) -> boolean,
	Replicate: (self: Machine, targets: { Player }?) -> boolean,
	Unreplicate: (self: Machine) -> boolean,
	SetReplicationTargets: (self: Machine, targets: { Player }?) -> boolean,
	SyncReplication: (self: Machine, targets: { Player }?) -> boolean,
}

return nil

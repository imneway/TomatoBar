import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, timerFired, skipRest, startNext
}

enum TBStateMachineStates: StateType {
    /* workDone and restDone are used in manual mode to wait for user confirmation */
    case idle, work, workDone, rest, restDone
}

--!strict

-- exposes the public Promily Promise API

local module = {}

--————————————————————————————————————————————————————————————————————--

local version = "1.2.5"

--————————————————————————————————————————————————————————————————————--

local adapters = script:WaitForChild("adapters")
local combinators = script:WaitForChild("combinators")
local concurrency = script:WaitForChild("concurrency")
local core = script:WaitForChild("core")

local cancellation = require(core:WaitForChild("cancellation"))
local collection = require(combinators:WaitForChild("collection"))
local control = require(combinators:WaitForChild("control"))
local errors = require(core:WaitForChild("errors"))
local promiseModule = require(core:WaitForChild("promise"))
local queueModule = require(concurrency:WaitForChild("queue"))
local robloxAdapters = require(adapters:WaitForChild("roblox"))
local scopeModule = require(core:WaitForChild("scope"))
local semaphoreModule = require(concurrency:WaitForChild("semaphore"))
local singleFlightModule = require(concurrency:WaitForChild("singleFlight"))

--————————————————————————————————————————————————————————————————————--

export type aggregateError = errors.aggregateError
export type cancellationSource = cancellation.source
export type cancellationToken = promiseModule.cancellationToken
export type cancelledAttemptError = errors.cancelledAttemptError
export type cancelledInputError = errors.cancelledInputError
export type cancelledMapperError = errors.cancelledMapperError
export type childOptions = robloxAdapters.childOptions
export type connection = promiseModule.connection
export type deferred<T> = promiseModule.deferred<T>
export type diagnosticsSnapshot = promiseModule.diagnosticsSnapshot
export type diagnosticsStats = promiseModule.diagnosticsStats
export type eventOptions = robloxAdapters.eventOptions
export type insufficientInputsError = errors.insufficientInputsError
export type mapOptions = collection.mapOptions
export type observer<T> = promiseModule.observer<T>
export type partitionResult<T> = collection.partitionResult<T>
export type permit = semaphoreModule.permit
export type promiseBase = promiseModule.promiseBase
export type promise<T> = promiseModule.promise<T>
export type promiseResult<T> = promiseModule.result<T>
export type promiseStatus = promiseModule.promiseStatus
export type queue = queueModule.queue
export type queueClosedError = errors.queueClosedError
export type queueDeletedError = errors.queueDeletedError
export type queueFullError = errors.queueFullError
export type queueOptions = queueModule.queueOptions
export type retryOptions = control.retryOptions
export type scope = scopeModule.scope
export type semaphore = semaphoreModule.semaphore
export type semaphoreDeletedError = errors.semaphoreDeletedError
export type settledResult<T> = collection.settledResult<T>
export type singleFlight = singleFlightModule.singleFlight
export type singleFlightDeletedError = errors.singleFlightDeletedError
export type singleFlightKey = singleFlightModule.singleFlightKey
export type timeoutOptions = promiseModule.timeoutOptions
export type valueOptions<T> = robloxAdapters.valueOptions<T>

--————————————————————————————————————————————————————————————————————--

--- Returns the Promily package version.
---@return string version Semantic package version.
function module.getVersion(): string
	return version
end

--————————————————————————————————————————————————————————————————————--

--- Creates a new Promise and runs its executor asynchronously.
---@generic T
---@param executor fun(resolve: fun(value: T | promise<T>), reject: fun(reason: any), onCancel: fun(callback: fun(reason: any?)): boolean) Promise executor.
---@param token cancellationToken? Optional cancellation token linked to the created Promise.
---@return promise<T> promiseValue Created Promise.
function module.new<T>(
	executor: (
		resolve: (value: T | promise<T>) -> (),
		reject: (reason: any) -> (),
		onCancel: (callback: (reason: any?) -> ()) -> boolean
	) -> (),
	token: cancellationToken?
): promise<T>
	return promiseModule.new(executor, token)
end

--————————————————————————————————————————————————————————————————————--

--- Creates a deferred Promise with explicit resolve, reject, and cancel functions.
---@generic T
---@param token cancellationToken? Optional cancellation token linked to the deferred Promise.
---@return deferred<T> deferredValue Deferred controller and Promise.
function module.defer<T>(token: cancellationToken?): deferred<T>
	return promiseModule.defer(token)
end

--————————————————————————————————————————————————————————————————————--

--- Wraps a value in a resolved Promise or returns an existing Promily Promise unchanged.
---@generic T
---@param value T | promise<T> Value or existing Promise.
---@return promise<T> promiseValue Resolved or existing Promise.
function module.resolve<T>(value: T | promise<T>): promise<T>
	return promiseModule.resolve(value)
end

--————————————————————————————————————————————————————————————————————--

--- Creates an immediately rejected Promise.
---@generic T
---@param reason any Rejection reason.
---@return promise<T> promiseValue Rejected Promise.
function module.reject<T>(reason: any): promise<T>
	return promiseModule.reject(reason)
end

--————————————————————————————————————————————————————————————————————--

--- Creates an immediately cancelled Promise.
---@generic T
---@param reason any? Optional cancellation reason.
---@return promise<T> promiseValue Cancelled Promise.
function module.cancelled<T>(reason: any?): promise<T>
	return promiseModule.cancelled(reason)
end

--————————————————————————————————————————————————————————————————————--

--- Creates a Promise that stays pending until it is cancelled.
---@generic T
---@param token cancellationToken? Optional cancellation token.
---@return promise<T> promiseValue Pending Promise.
function module.never<T>(token: cancellationToken?): promise<T>
	return promiseModule.new(function() end, token)
end

--————————————————————————————————————————————————————————————————————--

--- Executes a callback inside Promise error handling and adopts its returned Promise when needed.
---@generic T
---@param callback fun(): T | promise<T> Callback to execute.
---@param token cancellationToken? Optional cancellation token.
---@return promise<T> promiseValue Promise for the callback result.
function module.try<T>(callback: () -> T | promise<T>, token: cancellationToken?): promise<T>
	return promiseModule.try(callback, token)
end

--————————————————————————————————————————————————————————————————————--

--- Converts a throwing function into a function that always returns a Promily Promise.
---@param callback fun(...: any): any Function to wrap.
---@return fun(...: any): promise<any> wrapped Wrapped Promise-returning function.
function module.wrap(callback: (...any) -> any): (...any) -> promise<any>
	return promiseModule.wrap(callback)
end

--————————————————————————————————————————————————————————————————————--

--- Checks whether a value is a Promily Promise.
---@param value any Value to inspect.
---@return boolean isPromise Whether the value is a Promily Promise.
function module.is(value: any): boolean
	return promiseModule.is(value)
end

--————————————————————————————————————————————————————————————————————--

--- Sets the global callback used for otherwise-unhandled rejections.
---@param callback fun(promiseValue: promise<any>, reason: any) Unhandled rejection callback.
function module.setUnhandledRejectionHandler(callback: (promiseValue: promise<any>, reason: any) -> ())
	promiseModule.setUnhandledRejectionHandler(callback)
end

--————————————————————————————————————————————————————————————————————--

--- Creates a cancellation source and read-only token pair.
---@return cancellationSource source Cancellation source.
function module.createCancellationSource(): cancellationSource
	return cancellation.new()
end

--————————————————————————————————————————————————————————————————————--

--- Creates a lifecycle scope that owns and cancels tracked Promises.
---@return scope scopeValue Promise scope.
function module.createScope(): scope
	return scopeModule.new()
end

--————————————————————————————————————————————————————————————————————--

--- Creates a bounded asynchronous work queue.
---@param options queueOptions? Queue concurrency and pending-capacity options.
---@return queue queueValue Work queue.
function module.createQueue(options: queueOptions?): queue
	return queueModule.new(options)
end

--————————————————————————————————————————————————————————————————————--

--- Creates a semaphore for limiting simultaneous asynchronous work.
---@param limit number Maximum simultaneous permits.
---@return semaphore semaphoreValue Semaphore.
function module.createSemaphore(limit: number): semaphore
	return semaphoreModule.new(limit)
end

--————————————————————————————————————————————————————————————————————--

--- Creates a single-flight group that deduplicates concurrent work by key.
---@return singleFlight singleFlightValue Single-flight group.
function module.createSingleFlight(): singleFlight
	return singleFlightModule.new()
end

--————————————————————————————————————————————————————————————————————--

--- Creates an independently cancellable consumer branch of a source Promise.
--- Cancelling the branch disconnects it without cancelling the source.
---@generic T
---@param source T | promise<T> Source value or Promise.
---@return promise<T> branch Independent consumer Promise.
function module.fork<T>(source: T | promise<T>): promise<T>
	return promiseModule.resolve(source).fork() :: any
end

--————————————————————————————————————————————————————————————————————--

--- Mirrors a source Promise while also cancelling the consumer when the token is cancelled.
--- Token cancellation does not cancel the source Promise.
---@generic T
---@param source T | promise<T> Source value or Promise.
---@param token cancellationToken Cancellation token for the consumer branch.
---@return promise<T> branch Token-bound consumer Promise.
function module.withCancellation<T>(source: T | promise<T>, token: cancellationToken): promise<T>
	return promiseModule.resolve(source).withCancellation(token) :: any
end

--————————————————————————————————————————————————————————————————————--

--- Resolves when every input resolves, preserving input order.
---@generic T
---@param values {T | promise<T>} Input values or Promises.
---@return promise<{T}> values Resolved values.
function module.all<T>(values: {T | promise<T>}): promise<{T}>
	return collection.all(values)
end

--————————————————————————————————————————————————————————————————————--

--- Waits for every input and returns each settlement without rejecting for an individual failure.
---@generic T
---@param values {T | promise<T>} Input values or Promises.
---@return promise<{settledResult<T>}> results Settlement results in input order.
function module.allSettled<T>(values: {T | promise<T>}): promise<{settledResult<T>}>
	return collection.allSettled(values)
end

--————————————————————————————————————————————————————————————————————--

--- Settles with the first input to settle.
---@generic T
---@param values {T | promise<T>} Values or Promises to race.
---@return promise<T> value First settlement.
function module.race<T>(values: {T | promise<T>}): promise<T>
	return collection.race(values)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves with the first successfully resolved input or rejects with AggregateError when all fail.
---@generic T
---@param values {T | promise<T>} Values or Promises.
---@return promise<T> value First resolved value.
function module.any<T>(values: {T | promise<T>}): promise<T>
	return collection.any(values)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves after the requested number of inputs resolve.
---@generic T
---@param values {T | promise<T>} Values or Promises.
---@param count number Required number of successful resolutions.
---@return promise<{T}> values Successfully resolved values.
function module.some<T>(values: {T | promise<T>}, count: number): promise<{T}>
	return collection.some(values, count)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves every keyed Promise and preserves its string key.
---@generic T
---@param values {[string]: T | promise<T>} Keyed values or Promises.
---@return promise<{[string]: T}> values Resolved keyed values.
function module.props<T>(values: {[string]: T | promise<T>}): promise<{[string]: T}>
	return collection.props(values)
end

--————————————————————————————————————————————————————————————————————--

--- Waits for every keyed Promise and captures resolution, rejection, or cancellation per key.
---@generic T
---@param values {[string]: T | promise<T>} Keyed values or Promises.
---@return promise<{[string]: settledResult<T>}> results Settlement result for every key.
function module.propsSettled<T>(
	values: {[string]: T | promise<T>}
): promise<{[string]: settledResult<T>}>
	return collection.propsSettled(values)
end

--————————————————————————————————————————————————————————————————————--

--- Maps values with optional bounded concurrency.
---@generic T
---@generic R
---@param values {T} Values to map.
---@param mapper fun(value: T, index: number): R | promise<R> Mapper callback.
---@param options mapOptions? Optional concurrency limit.
---@return promise<{R}> values Mapped values in input order.
function module.map<T, R>(
	values: {T},
	mapper: (value: T, index: number) -> R | promise<R>,
	options: mapOptions?
): promise<{R}>
	return collection.map(values, mapper, options)
end

--————————————————————————————————————————————————————————————————————--

--- Maps every value while capturing each mapper settlement instead of failing fast.
---@generic T
---@generic R
---@param values {T} Values to map.
---@param mapper fun(value: T, index: number): R | promise<R> Mapper callback.
---@param options mapOptions? Optional concurrency limit.
---@return promise<{settledResult<R>}> results Mapper settlement results in input order.
function module.mapSettled<T, R>(
	values: {T},
	mapper: (value: T, index: number) -> R | promise<R>,
	options: mapOptions?
): promise<{settledResult<R>}>
	return collection.mapSettled(values, mapper, options)
end

--————————————————————————————————————————————————————————————————————--

--- Filters values with a synchronous or asynchronous predicate while preserving input order.
---@generic T
---@param values {T} Values to filter.
---@param predicate fun(value: T, index: number): boolean | promise<boolean> Predicate callback.
---@param options mapOptions? Optional concurrency limit.
---@return promise<{T}> values Included values in input order.
function module.filter<T>(
	values: {T},
	predicate: (value: T, index: number) -> boolean | promise<boolean>,
	options: mapOptions?
): promise<{T}>
	return collection.filter(values, predicate, options)
end

--————————————————————————————————————————————————————————————————————--

--- Finds the first input-order value whose synchronous or asynchronous predicate resolves true.
---@generic T
---@param values {T} Values to search.
---@param predicate fun(value: T, index: number): boolean | promise<boolean> Predicate callback.
---@param options mapOptions? Optional concurrency limit.
---@return promise<T?> value First matching value, or nil when no value matches.
function module.find<T>(
	values: {T},
	predicate: (value: T, index: number) -> boolean | promise<boolean>,
	options: mapOptions?
): promise<T?>
	return collection.find(values, predicate, options)
end

--————————————————————————————————————————————————————————————————————--

--- Partitions values into matched and unmatched arrays using one predicate pass.
---@generic T
---@param values {T} Values to partition.
---@param predicate fun(value: T, index: number): boolean | promise<boolean> Predicate callback.
---@param options mapOptions? Optional concurrency limit.
---@return promise<partitionResult<T>> result Partitioned values.
function module.partition<T>(
	values: {T},
	predicate: (value: T, index: number) -> boolean | promise<boolean>,
	options: mapOptions?
): promise<partitionResult<T>>
	return collection.partition(values, predicate, options)
end

--————————————————————————————————————————————————————————————————————--

--- Runs a side-effect callback for every value and resolves with the original values.
---@generic T
---@param values {T} Values to visit.
---@param callback fun(value: T, index: number): any | promise<any> Side-effect callback.
---@param options mapOptions? Optional concurrency limit.
---@return promise<{T}> values Original values after all callbacks finish.
function module.each<T>(
	values: {T},
	callback: (value: T, index: number) -> any | promise<any>,
	options: mapOptions?
): promise<{T}>
	return collection.each(values, callback, options)
end

--————————————————————————————————————————————————————————————————————--

--- Runs lazy tasks sequentially and resolves with every result.
---@generic R
---@param tasks {fun(): R | promise<R>} Lazy tasks.
---@return promise<{R}> values Results in task order.
function module.sequence<R>(tasks: {() -> R | promise<R>}): promise<{R}>
	return collection.sequence(tasks)
end

--————————————————————————————————————————————————————————————————————--

--- Runs lazy tasks one at a time until one resolves successfully.
---@generic T
---@param tasks {fun(): T | promise<T>} Lazy tasks ordered by preference.
---@return promise<T> value First successful result.
function module.firstResolved<T>(tasks: {() -> T | promise<T>}): promise<T>
	return collection.firstResolved(tasks)
end

--————————————————————————————————————————————————————————————————————--

--- Reduces values through a synchronous or asynchronous reducer.
---@generic T
---@generic R
---@param values {T} Values to reduce.
---@param reducer fun(accumulator: R, value: T, index: number): R | promise<R> Reducer callback.
---@param initialValue R Initial accumulator value.
---@return promise<R> value Final accumulator.
function module.reduce<T, R>(
	values: {T},
	reducer: (accumulator: R, value: T, index: number) -> R | promise<R>,
	initialValue: R
): promise<R>
	return collection.reduce(values, reducer, initialValue)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves after a delay with an optional value.
---@generic T
---@param seconds number Non-negative delay in seconds.
---@param value T? Optional resolved value.
---@return promise<T?> promiseValue Delayed Promise.
function module.delay<T>(seconds: number, value: T?): promise<T?>
	return control.delay(seconds, value)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves after a delay without a payload.
---@param seconds number Non-negative delay in seconds.
---@return promise<nil> promiseValue Sleep Promise.
function module.sleep(seconds: number): promise<nil>
	return control.sleep(seconds)
end

--————————————————————————————————————————————————————————————————————--

--- Creates a Promise that rejects after a delay unless cancelled first.
---@generic T
---@param seconds number Non-negative delay in seconds.
---@param reason any Rejection reason.
---@return promise<T> promiseValue Rejecting timer Promise.
function module.rejectAfter<T>(seconds: number, reason: any): promise<T>
	return control.rejectAfter(seconds, reason)
end

--————————————————————————————————————————————————————————————————————--

--- Applies a relative timeout to a source Promise.
---@generic T
---@param source T | promise<T> Source value or Promise.
---@param seconds number Timeout duration in seconds.
---@param options timeoutOptions? Timeout fallback or reason options.
---@return promise<T> promiseValue Timed source Promise.
function module.timeout<T>(source: T | promise<T>, seconds: number, options: timeoutOptions?): promise<T>
	return control.timeout(source, seconds, options)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves with a fallback when the source does not settle before the timeout.
---@generic T
---@generic R
---@param source T | promise<T> Source value or Promise.
---@param seconds number Timeout duration in seconds.
---@param fallback R | promise<R> Fallback value or Promise.
---@return promise<T | R> promiseValue Source or fallback result.
function module.timeoutOr<T, R>(
	source: T | promise<T>,
	seconds: number,
	fallback: R | promise<R>
): promise<T | R>
	return control.timeoutOr(source, seconds, fallback)
end

--————————————————————————————————————————————————————————————————————--

--- Applies an absolute os.clock() deadline to a source Promise.
---@generic T
---@param source T | promise<T> Source value or Promise.
---@param deadlineTime number Absolute os.clock() deadline.
---@param reason any? Optional rejection reason when the deadline is exceeded.
---@return promise<T> promiseValue Deadline-bound Promise.
function module.deadline<T>(source: T | promise<T>, deadlineTime: number, reason: any?): promise<T>
	return promiseModule.resolve(source).deadline(deadlineTime, reason) :: any
end

--————————————————————————————————————————————————————————————————————--

--- Retries a lazy Promise-producing operation with optional delay, backoff, and jitter.
---@generic T
---@param callback fun(attempt: number): T | promise<T> Attempt callback.
---@param options retryOptions? Retry policy.
---@return promise<T> promiseValue Retried operation.
function module.retry<T>(callback: (attempt: number) -> T | promise<T>, options: retryOptions?): promise<T>
	return control.retry(callback, options)
end

--————————————————————————————————————————————————————————————————————--

--- Runs a lazy callback after a delay and adopts its result.
---@generic T
---@param seconds number Non-negative delay in seconds.
---@param callback fun(): T | promise<T> Callback to run after the delay.
---@return promise<T> promiseValue Delayed callback result.
function module.after<T>(seconds: number, callback: () -> T | promise<T>): promise<T>
	return control.sleep(seconds).andThen(function()
		return callback()
	end) :: any
end

--————————————————————————————————————————————————————————————————————--

--- Resolves from the next matching Roblox signal emission.
---@param signal RBXScriptSignal Roblox signal to observe.
---@param options eventOptions? Event filtering and timeout options.
---@return promise<{any}> promiseValue Packed signal arguments.
function module.fromEvent(signal: RBXScriptSignal, options: eventOptions?): promise<{any}>
	return robloxAdapters.fromEvent(signal, options)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves when a Roblox property reaches the requested predicate or target value.
---@generic T
---@param instance Instance Instance containing the property.
---@param propertyName string Property name.
---@param options valueOptions<T>? Value matching and timeout options.
---@return promise<T> promiseValue Matching property value.
function module.fromProperty<T>(instance: Instance, propertyName: string, options: valueOptions<T>?): promise<T>
	return robloxAdapters.fromProperty(instance, propertyName, options)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves when a Roblox attribute reaches the requested predicate or target value.
---@generic T
---@param instance Instance Instance containing the attribute.
---@param attributeName string Attribute name.
---@param options valueOptions<T>? Value matching and timeout options.
---@return promise<T> promiseValue Matching attribute value.
function module.fromAttribute<T>(instance: Instance, attributeName: string, options: valueOptions<T>?): promise<T>
	return robloxAdapters.fromAttribute(instance, attributeName, options)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves when a named child exists under the parent.
---@param parent Instance Parent instance.
---@param name string Child name.
---@param options childOptions? Child matching and timeout options.
---@return promise<Instance> promiseValue Matching child.
function module.fromChild(parent: Instance, name: string, options: childOptions?): promise<Instance>
	return robloxAdapters.fromChild(parent, name, options)
end

--————————————————————————————————————————————————————————————————————--

module.diagnostics = table.freeze({
	--- Returns pending Promises sorted longest-pending first.
	---@param limit number? Optional maximum result count.
	---@return {diagnosticsSnapshot} snapshots Pending Promise snapshots.
	getLongestPending = function(limit: number?): {diagnosticsSnapshot}
		return promiseModule.getPendingSnapshots(limit)
	end,

	--- Returns pending Promises sorted longest-pending first.
	---@param limit number? Optional maximum result count.
	---@return {diagnosticsSnapshot} snapshots Pending Promise snapshots.
	getPending = function(limit: number?): {diagnosticsSnapshot}
		return promiseModule.getPendingSnapshots(limit)
	end,

	--- Returns lifetime and currently-live Promise counts.
	---@return diagnosticsStats stats Promise diagnostic counters.
	getStats = function(): diagnosticsStats
		return promiseModule.getDiagnosticsStats()
	end,
})

module.status = promiseModule.getStatusTable()

--————————————————————————————————————————————————————————————————————--

return module

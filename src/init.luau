--!strict

-- exposes the public Promily Promise API

local module = {}

--————————————————————————————————————————————————————————————————————--

local version = "1.0.0"

--————————————————————————————————————————————————————————————————————--

local adapters = script:WaitForChild("adapters")
local combinators = script:WaitForChild("combinators")
local core = script:WaitForChild("core")

local cancellation = require(core:WaitForChild("cancellation"))
local collection = require(combinators:WaitForChild("collection"))
local control = require(combinators:WaitForChild("control"))
local promiseModule = require(core:WaitForChild("promise"))
local robloxAdapters = require(adapters:WaitForChild("roblox"))
local scopeModule = require(core:WaitForChild("scope"))

--————————————————————————————————————————————————————————————————————--

export type cancellationSource = cancellation.source
export type cancellationToken = promiseModule.cancellationToken
export type childOptions = robloxAdapters.childOptions
export type connection = promiseModule.connection
export type deferred<T> = promiseModule.deferred<T>
export type eventOptions = robloxAdapters.eventOptions
export type mapOptions = collection.mapOptions
export type observer<T> = promiseModule.observer<T>
export type promise<T> = promiseModule.promise<T>
export type promiseResult<T> = promiseModule.result<T>
export type promiseStatus = promiseModule.promiseStatus
export type retryOptions = control.retryOptions
export type scope = scopeModule.scope
export type settledResult<T> = collection.settledResult<T>
export type timeoutOptions = promiseModule.timeoutOptions
export type valueOptions<T> = robloxAdapters.valueOptions<T>

--————————————————————————————————————————————————————————————————————--

function module.getVersion(): string
	return version
end

--————————————————————————————————————————————————————————————————————--

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

function module.defer<T>(token: cancellationToken?): deferred<T>
	return promiseModule.defer(token)
end

--————————————————————————————————————————————————————————————————————--

function module.resolve<T>(value: T | promise<T>): promise<T>
	return promiseModule.resolve(value)
end

--————————————————————————————————————————————————————————————————————--

function module.reject<T>(reason: any): promise<T>
	return promiseModule.reject(reason)
end

--————————————————————————————————————————————————————————————————————--

function module.cancelled<T>(reason: any?): promise<T>
	return promiseModule.cancelled(reason)
end

--————————————————————————————————————————————————————————————————————--

function module.never<T>(token: cancellationToken?): promise<T>
	return promiseModule.new(function() end, token)
end

--————————————————————————————————————————————————————————————————————--

function module.try<T>(callback: () -> T | promise<T>, token: cancellationToken?): promise<T>
	return promiseModule.try(callback, token)
end

--————————————————————————————————————————————————————————————————————--

function module.wrap(callback: (...any) -> any): (...any) -> promise<any>
	return promiseModule.wrap(callback)
end

--————————————————————————————————————————————————————————————————————--

function module.is(value: any): boolean
	return promiseModule.is(value)
end

--————————————————————————————————————————————————————————————————————--

function module.setUnhandledRejectionHandler(callback: (promiseValue: promise<any>, reason: any) -> ())
	promiseModule.setUnhandledRejectionHandler(callback)
end

--————————————————————————————————————————————————————————————————————--

function module.createCancellationSource(): cancellationSource
	return cancellation.new()
end

--————————————————————————————————————————————————————————————————————--

function module.createScope(): scope
	return scopeModule.new()
end

--————————————————————————————————————————————————————————————————————--

function module.all<T>(values: { T | promise<T> }): promise<{ T }>
	return collection.all(values)
end

--————————————————————————————————————————————————————————————————————--

function module.allSettled<T>(values: { T | promise<T> }): promise<{ settledResult<T> }>
	return collection.allSettled(values)
end

--————————————————————————————————————————————————————————————————————--

function module.race<T>(values: { T | promise<T> }): promise<T>
	return collection.race(values)
end

--————————————————————————————————————————————————————————————————————--

function module.any<T>(values: { T | promise<T> }): promise<T>
	return collection.any(values)
end

--————————————————————————————————————————————————————————————————————--

function module.some<T>(values: { T | promise<T> }, count: number): promise<{ T }>
	return collection.some(values, count)
end

--————————————————————————————————————————————————————————————————————--

function module.props<T>(values: { [string]: T | promise<T> }): promise<{ [string]: T }>
	return collection.props(values)
end

--————————————————————————————————————————————————————————————————————--

function module.map<T, R>(
	values: { T },
	mapper: (value: T, index: number) -> R | promise<R>,
	options: mapOptions?
): promise<{ R }>
	return collection.map(values, mapper, options)
end

--————————————————————————————————————————————————————————————————————--

function module.each<T>(
	values: { T },
	callback: (value: T, index: number) -> any | promise<any>,
	options: mapOptions?
): promise<{ T }>
	return collection.each(values, callback, options)
end

--————————————————————————————————————————————————————————————————————--

function module.sequence<R>(tasks: { () -> R | promise<R> }): promise<{ R }>
	return collection.sequence(tasks)
end

--————————————————————————————————————————————————————————————————————--

function module.reduce<T, R>(
	values: { T },
	reducer: (accumulator: R, value: T, index: number) -> R | promise<R>,
	initialValue: R
): promise<R>
	return collection.reduce(values, reducer, initialValue)
end

--————————————————————————————————————————————————————————————————————--

function module.delay<T>(seconds: number, value: T?): promise<T?>
	return control.delay(seconds, value)
end

--————————————————————————————————————————————————————————————————————--

function module.sleep(seconds: number): promise<nil>
	return control.sleep(seconds)
end

--————————————————————————————————————————————————————————————————————--

function module.timeout<T>(source: T | promise<T>, seconds: number, options: timeoutOptions?): promise<T>
	return control.timeout(source, seconds, options)
end

--————————————————————————————————————————————————————————————————————--

function module.timeoutOr<T, R>(source: T | promise<T>, seconds: number, fallback: R | promise<R>): promise<T | R>
	return control.timeoutOr(source, seconds, fallback)
end

--————————————————————————————————————————————————————————————————————--

function module.retry<T>(callback: (attempt: number) -> T | promise<T>, options: retryOptions?): promise<T>
	return control.retry(callback, options)
end

--————————————————————————————————————————————————————————————————————--

function module.after<T>(seconds: number, callback: () -> T | promise<T>): promise<T>
	return control.sleep(seconds).andThen(function()
		return callback()
	end)
end

--————————————————————————————————————————————————————————————————————--

function module.fromEvent(signal: RBXScriptSignal, options: eventOptions?): promise<{ any }>
	return robloxAdapters.fromEvent(signal, options)
end

--————————————————————————————————————————————————————————————————————--

function module.fromProperty<T>(instance: Instance, propertyName: string, options: valueOptions<T>?): promise<T>
	return robloxAdapters.fromProperty(instance, propertyName, options)
end

--————————————————————————————————————————————————————————————————————--

function module.fromAttribute<T>(instance: Instance, attributeName: string, options: valueOptions<T>?): promise<T>
	return robloxAdapters.fromAttribute(instance, attributeName, options)
end

--————————————————————————————————————————————————————————————————————--

function module.fromChild(parent: Instance, name: string, options: childOptions?): promise<Instance>
	return robloxAdapters.fromChild(parent, name, options)
end

--————————————————————————————————————————————————————————————————————--

module.status = promiseModule.getStatusTable()

--————————————————————————————————————————————————————————————————————--

return module

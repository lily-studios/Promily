# Promily Documentation & API Reference

> **Package:** Promily
> **Version:** `1.2.5`
> **Language:** Roblox Luau
> **Type mode:** `--!strict`
> **Repository:** `https://github.com/lily-studios/Promily`
> **Entry point:** `src/init.luau`

Promily is a Lily-native Promise package for Roblox Luau. It provides strict typed Promise composition, cancellation ownership, collection combinators, retry/timing helpers, Roblox event adapters, deferred resolvers, structured results, debug labels, and QoL utilities without polling or permanent frame loops.

This file is the consolidated Promily manual: setup, concepts, usage cookbook, full public API, returned-object APIs, option types, module responsibilities, sourcemap configuration, tests, and lifecycle behavior.

---

### Luau generic-call syntax and Promise chain typing

Generic declarations and type annotations use normal angle brackets, such as `promise<T>` and `function map<T, R>(...)`. When you explicitly provide type arguments to a **function call**, Luau uses double angle brackets:

```luau
local deferred = Promily.defer<<number>>()
local rejected = Promily.reject<<string>>("failed")
```

Luau currently rejects recursive generic table aliases that instantiate themselves with a different parameter, such as a literal `promise<T>.andThen<R>() -> promise<R>` alias. Promily keeps precise `promise<T>` typing on type-preserving methods and on the module-level generic APIs. Type-changing instance chains cross the exported `promiseBase` boundary so the package remains accepted by the current strict type checker without changing runtime Promise behavior.


## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Rojo and Sourcemap Setup](#rojo-and-sourcemap-setup)
- [Quick Start](#quick-start)
- [Promise Model](#promise-model)
- [Cancellation Model](#cancellation-model)
- [Unhandled Rejections](#unhandled-rejections)
- [Collection Ownership](#collection-ownership)
- [Practical Usage Cookbook](#practical-usage-cookbook)
- [Detailed `Promily.*` API](#detailed-promily-api)
- [Detailed `promise.*` API](#detailed-promise-api)
- [Deferred API](#deferred-api)
- [Cancellation Source and Token API](#cancellation-source-and-token-api)
- [Scope API](#scope-api)
- [Observer API](#observer-api)
- [Status and Result Types](#status-and-result-types)
- [Option Types](#option-types)
- [Module Responsibilities](#module-responsibilities)
- [Testing](#testing)
- [Performance and Lifecycle](#performance-and-lifecycle)
- [Literal Full API Index](#literal-full-api-index)

---

## Overview

Promily represents one eventual asynchronous settlement:

```text
Pending
├── Resolved
├── Rejected
└── Cancelled
```

A Promise settles exactly once. Later resolve/reject/cancel attempts do not replace the first terminal state.

Promily APIs use dot calls:

```lua
local promise = Promily.resolve(10)

promise.andThen(function(value)
	print(value)
end)

promise.cancel("owner closed")
```

Promily-owned APIs do not use colon syntax:

```lua
-- Correct
promise.andThen(callback)
scope.delete()
source.cancel(reason)

-- Incorrect for Promily-owned APIs
promise:andThen(callback)
scope:delete()
source:cancel(reason)
```

Roblox-owned methods keep Roblox syntax:

```lua
connection:Disconnect()
instance:GetAttribute("ready")
instance:Destroy()
```

---

## Installation

The package entry point is:

```text
src/init.luau
```

With the package mounted as a ModuleScript:

```lua
local replicatedStorage = game:GetService("ReplicatedStorage")

local Promily = require(replicatedStorage:WaitForChild("Promily"))
```

Check the installed version:

```lua
print(Promily.getVersion()) -- "1.2.5"
```

Promily has **11 source modules**, **46 public `Promily.*` functions**, **36 Promise instance methods**, and no runtime third-party dependencies.

---

## Rojo and Sourcemap Setup

Promily's package-style `default.project.json` is:

```json
{"name":"Promily","tree":{"$path":"src"}}
```

Generate a fresh sourcemap from the current source tree whenever your editor/LSP needs one:

```sh
rojo sourcemap default.project.json -o sourcemap.json
```

The repository intentionally ignores generated `sourcemap.json` files so they cannot become stale when modules are added or renamed.

For the dependency-free Studio test suite, use:

```json
{"name":"PromilyTests","tree":{"$className":"DataModel","ReplicatedStorage":{"Promily":{"$path":"src"}},"ServerScriptService":{"PromilyTests":{"$path":"tests"}}}}
```

This mounts the package under `ReplicatedStorage.Promily` and tests under `ServerScriptService.PromilyTests`.

---

## Quick Start

```lua
local Promily = require(path.Promily)

local request = Promily.new(function(resolve, reject, onCancel)
	local connection

	connection = responseEvent:Connect(function(success, payload)
		connection:Disconnect()

		if success then
			resolve(payload)
			return
		end

		reject(payload)
	end)

	onCancel(function(_reason)
		connection:Disconnect()
	end)
end)

request
	.andThen(function(value)
		print("Resolved:", value)
	end)
	.catch(function(reason)
		warn("Rejected:", reason)
	end)
```

Add a timeout:

```lua
local value = request
	.timeout(5)
	.expect()
```

---

## Promily 1.2 Promise Additions

Promily 1.2 expands the Promise-focused API without adding unrelated state, signal, UI, or scheduler systems:

- `promise.catchCancel()` / `catchCancelReturn()` for explicit cancellation recovery.
- `promise.fork()` and `Promily.fork()` for independently cancellable consumer branches.
- `promise.withCancellation()` and `Promily.withCancellation()` for consumer-local token cancellation without cancelling shared source work.
- `promise.tapCancel()` and `tapSettled()` for cancellation/settlement side effects that preserve the original settlement.
- `Promily.mapSettled()` for bounded concurrent mapping that captures every mapper settlement.
- `Promily.filter()`, `find()`, and `partition()` with synchronous or asynchronous predicates.
- `Promily.propsSettled()` for keyed all-settled behavior.
- `Promily.firstResolved()` for lazy sequential fallback tasks.
- `Promily.rejectAfter()` for a cancellable delayed rejection useful in races and deadlines.
- `---@param`, `---@return`, `---@generic`, and behavior documentation across every exported `module.*` function in `src`, plus the new Promise instance methods.

Promily 1.1's production controls remain available: queues, semaphores, single-flight deduplication, absolute deadlines, cancellation listeners, diagnostics, and structured error values.

## Promise Model

### Asynchronous observer delivery

Settlement observers and chain callbacks are delivered through one-shot deferred scheduling. Promily does not maintain a permanent scheduler loop.

### Promise adoption

Resolving or returning another Promily Promise adopts that Promise's eventual settlement:

```lua
loadProfile(userId)
	.andThen(function(profile)
		return loadInventory(profile)
	end)
```

### Chained rejection ownership

When a chain forwards a rejection, the downstream Promise becomes responsible for handling it.

### One terminal state

```text
Pending -> Resolved
Pending -> Rejected
Pending -> Cancelled
```

A terminal Promise does not transition again.

---

## Cancellation Model

Promily has three cancellation layers:

### Promise cancellation

```lua
promise.cancel("screen closed")
```

Cancelling a Promise runs its registered cancellation cleanup.

### Cancellation source/token

```lua
local source = Promily.createCancellationSource()
local token = source.getToken()

local promise = Promily.new(executor, token)

source.cancel("controller deleted")
```

The source owns mutation. The token exposes read-only cancellation observation.

### Cancellation scope

```lua
local scope = Promily.createScope()

scope.track(loadProfile())
scope.track(loadSettings())

scope.delete()
```

A scope is useful when a page/controller owns many Promise operations.

### Chain direction

Parent cancellation propagates downward to chained children. Cancelling a child detaches that child from the parent; it does not silently cancel caller-owned parent work.

---

## Unhandled Rejections

Promily reports terminal rejected Promises that have no rejection handler.

Default behavior uses `warn()` and includes the Promise label when available.

```lua
Promily.setUnhandledRejectionHandler(function(promiseValue, reason)
	warn(
		promiseValue.getId(),
		promiseValue.getLabel(),
		reason
	)
end)
```

`observeSettled()` is intentionally rejection-neutral, while `toResult()` intentionally converts/handles rejection by turning settlement into resolved result data.

---

## Collection Ownership

Collection helpers such as `all`, `race`, `any`, `some`, and `map` observe their supplied inputs.

They do **not** automatically cancel caller-owned input Promises merely because the aggregate settles early.

If the aggregate should own those input operations, use an explicit scope:

```lua
local scope = Promily.createScope()

local requests = {
	scope.track(requestA()),
	scope.track(requestB()),
	scope.track(requestC()),
}

Promily.all(requests)
	.finally(function()
		scope.delete()
	end)
```

---

## Practical Usage Cookbook

> Practical patterns for `Promily`
> Repository: `https://github.com/lily-studios/Promily`

This file focuses on **how to use Promily in real Roblox systems**.

For exact signatures and types, see [`API.md`](API.md).

---

# Table of Contents

- [Basic Promise Patterns](#basic-promise-patterns)
- [Error Handling](#error-handling)
- [Cancellation](#cancellation)
- [Cancellation Sources](#cancellation-sources)
- [Cancellation Scopes](#cancellation-scopes)
- [Deferred Promises](#deferred-promises)
- [Wrapping Existing Functions](#wrapping-existing-functions)
- [Parallel Work](#parallel-work)
- [First Successful Result](#first-successful-result)
- [Race Patterns](#race-patterns)
- [Partial Success](#partial-success)
- [Keyed Resolution](#keyed-resolution)
- [Concurrency-Limited Work](#concurrency-limited-work)
- [Sequential Work](#sequential-work)
- [Async Reduction](#async-reduction)
- [Timing](#timing)
- [Timeouts](#timeouts)
- [Retries](#retries)
- [Roblox Events](#roblox-events)
- [Roblox Attributes](#roblox-attributes)
- [Roblox Properties](#roblox-properties)
- [Waiting for Children](#waiting-for-children)
- [UI Lifecycle](#ui-lifecycle)
- [Remote Requests](#remote-requests)
- [Data Loading](#data-loading)
- [Caching](#caching)
- [Fallback Chains](#fallback-chains)
- [Loading Screens](#loading-screens)
- [Debounce-like Promise Work](#debounce-like-promise-work)
- [Result Objects](#result-objects)
- [Debugging](#debugging)
- [Cleanup Patterns](#cleanup-patterns)
- [Common Anti-Patterns](#common-anti-patterns)

---

# Basic Promise Patterns

## Resolve immediately

```lua
local promise = Promily.resolve(10)

promise.andThen(function(value)
	print(value)
end)
```

## Reject immediately

```lua
Promily.reject("failed")
	.catch(function(reason)
		warn(reason)
	end)
```

## Create custom async work

```lua
local promise = Promily.new(function(resolve, reject, onCancel)
	local thread = task.delay(1, function()
		resolve("done")
	end)

	onCancel(function(_reason)
		task.cancel(thread)
	end)
end)
```

## Chain transformations

```lua
local result = Promily.resolve(5)
	.andThen(function(value)
		return value * 2
	end)
	.andThen(function(value)
		return value + 10
	end)
	.expect()

print(result) -- 20
```

## Return another Promise inside `andThen`

```lua
loadUser(userId)
	.andThen(function(user)
		return loadInventory(user)
	end)
	.andThen(function(inventory)
		print(inventory)
	end)
```

Promily automatically adopts returned Promises.

---

# Error Handling

## Recover from an error

```lua
local result = request()
	.catch(function(reason)
		warn(reason)

		return fallbackValue
	end)
	.expect()
```

## Log without recovering

```lua
request()
	.tapError(function(reason)
		warn("Request failed:", reason)
	end)
	.catch(function()
		return fallbackValue
	end)
```

## Transform one error into another

```lua
request()
	.catch(function(reason)
		return Promily.reject({
			kind = "ProfileLoadFailed",
			cause = reason,
		})
	end)
```

## Always clean up

```lua
request()
	.finally(function()
		hideLoadingIndicator()
	end)
```

## Async cleanup in `finally`

```lua
request()
	.finally(function()
		return saveTemporaryState()
	end)
```

Promily waits for the cleanup Promise before preserving the original settlement.

---

# Cancellation

## Cancel owned async work

```lua
local promise = Promily.new(function(resolve, _reject, onCancel)
	local timer = task.delay(5, function()
		resolve("finished")
	end)

	onCancel(function(_reason)
		task.cancel(timer)
	end)
end)

promise.cancel("screen closed")
```

## Read the cancellation reason

```lua
local promise = Promily.new(function(_resolve, _reject, onCancel)
	onCancel(function(reason)
		print("Cancelled:", reason)
	end)
end)

promise.cancel("player left")
```

## Cancel a child chain

```lua
local parent = loadProfile()

local child = parent.andThen(function(profile)
	return profile.inventory
end)

child.cancel("inventory UI closed")
```

This detaches the child from the parent. It does not silently cancel caller-owned parent work.

---

# Cancellation Sources

A cancellation source is useful when several operations should share one cancellation condition.

```lua
local source = Promily.createCancellationSource()
local token = source.getToken()

local first = Promily.new(function(resolve)
	resolve(loadA())
end, token)

local second = Promily.new(function(resolve)
	resolve(loadB())
end, token)

source.cancel("controller deleted")
```

## Observe cancellation directly

```lua
local connection = token.onCancelled(function(reason)
	print("Token cancelled:", reason)
end)
```

## Assert active state

```lua
token.throwIfCancelled()
```

With custom message:

```lua
token.throwIfCancelled("This controller is no longer active.")
```

---

# Cancellation Scopes

Scopes are one of the most useful Promily QoL features.

## Own several Promises with one scope

```lua
local scope = Promily.createScope()

local profilePromise = scope.track(loadProfile())
local settingsPromise = scope.track(loadSettings())
local inventoryPromise = scope.track(loadInventory())

-- Later:
scope.cancel("page closed")
```

## Create Promise work directly inside a scope

```lua
local scope = Promily.createScope()

local promise = scope.newPromise(function(resolve, _reject, onCancel)
	local connection = event:Connect(function(value)
		resolve(value)
	end)

	onCancel(function(_reason)
		connection:Disconnect()
	end)
end)
```

## Use scope lifetime for a UI controller

```lua
local scope = Promily.createScope()

function controller.open()
	scope.track(loadData())
	scope.track(loadImages())
end

function controller.close()
	scope.delete()
end
```

## Check active work

```lua
print(scope.getCount())
```

---

# Deferred Promises

Deferred Promises are useful when the resolver must live outside the constructor.

```lua
local deferred = Promily.defer<<string>>()

button.Activated:Connect(function()
	deferred.resolve("clicked")
end)

local result = deferred.promise.expect()
```

## External rejection

```lua
local deferred = Promily.defer<<number>>()

task.defer(function()
	deferred.reject("not available")
end)

deferred.promise.catch(warn)
```

## External cancellation

```lua
local deferred = Promily.defer()

deferred.cancel("owner deleted")
```

---

# Wrapping Existing Functions

## Wrap a synchronous function

```lua
local parseAsync = Promily.wrap(function(text: string)
	return HttpService:JSONDecode(text)
end)

parseAsync(jsonText)
	.andThen(function(data)
		print(data)
	end)
```

Errors thrown by the wrapped function become Promise rejections.

## Wrap a function returning a Promise

```lua
local loadAsync = Promily.wrap(function(userId)
	return loadProfile(userId)
end)
```

---

# Parallel Work

## Wait for everything

```lua
local results = Promily.all({
	loadProfile(),
	loadInventory(),
	loadSettings(),
}).expect()

local profile = results[1]
local inventory = results[2]
local settings = results[3]
```

## Mix normal values and Promises

```lua
local results = Promily.all({
	Promily.resolve("A"),
	"B",
	Promily.delay(.1, "C"),
}).expect()
```

## Parallel page initialization

```lua
local values = Promily.all({
	loadTheme(),
	loadPresets(),
	loadUserSettings(),
	loadCatalog(),
}).expect()
```

---

# First Successful Result

`Promily.any()` ignores failures until one input resolves.

```lua
local asset = Promily.any({
	loadFromMemoryCache(),
	loadFromDiskCache(),
	loadFromNetwork(),
}).expect()
```

If everything fails, the Promise rejects with an aggregate error.

---

# Race Patterns

`Promily.race()` settles from the first settled input, whether success or failure.

## Cache vs network

```lua
local value = Promily.race({
	readCache(),
	requestNetwork(),
}).expect()
```

## Operation vs explicit timeout Promise

```lua
local result = Promily.race({
	longOperation(),
	Promily.delay(5).andThen(function()
		return Promily.reject("manual timeout")
	end),
})
```

Usually `timeout()` is cleaner for simple timeout behavior.

---

# Partial Success

## Wait for every input without failing the whole group

```lua
local results = Promily.allSettled({
	loadA(),
	loadB(),
	loadC(),
}).expect()

for _, result in results do
	if result.status == Promily.status.resolved then
		print("success", result.value)
		continue
	end

	warn("failed", result.reason)
end
```

## Require only N successes

```lua
local fastestTwo = Promily.some({
	serverA(),
	serverB(),
	serverC(),
	serverD(),
}, 2).expect()
```

---

# Keyed Resolution

`Promily.props()` is useful when array indexes would make the code harder to read.

```lua
local data = Promily.props({
	profile = loadProfile(),
	inventory = loadInventory(),
	settings = loadSettings(),
}).expect()

print(data.profile)
print(data.inventory)
print(data.settings)
```

---

# Concurrency-Limited Work

Avoid starting hundreds of expensive operations at once.

```lua
local loadedAssets = Promily.map(
	assetIds,
	function(assetId)
		return loadAsset(assetId)
	end,
	{
		concurrency = 4,
	}
).expect()
```

## Save players with controlled concurrency

```lua
Promily.map(
	players,
	function(player)
		return savePlayer(player)
	end,
	{
		concurrency = 3,
	}
).expect()
```

## Preserve order

Even if operations finish out of order, result positions match input positions.

```lua
local results = Promily.map(
	{1, 2, 3},
	function(value)
		return Promily.delay(math.random(), value * 10)
	end,
	{
		concurrency = 3,
	}
).expect()

-- results is still:
-- {10, 20, 30}
```

---

# `each`

Use `each()` when you care about the original inputs after the async operation.

```lua
local savedPlayers = Promily.each(
	players,
	function(player)
		return savePlayer(player)
	end,
	{
		concurrency = 4,
	}
).expect()
```

`savedPlayers` contains the original players.

---

# Sequential Work

## Sequence task factories

```lua
local results = Promily.sequence({
	function()
		return connectDatabase()
	end,
	function()
		return loadConfiguration()
	end,
	function()
		return startRuntime()
	end,
}).expect()
```

## Initialization pipeline

```lua
Promily.sequence({
	initializeFolders,
	initializeRemotes,
	initializeProfiles,
	initializeInterface,
})
	.andThen(function()
		print("Initialization complete")
	end)
```

---

# Async Reduction

## Sum async-transformed values

```lua
local total = Promily.reduce(
	values,
	function(accumulator, value)
		return loadWeight(value)
			.andThen(function(weight)
				return accumulator + weight
			end)
	end,
	0
).expect()
```

## Build a lookup table sequentially

```lua
local lookup = Promily.reduce(
	ids,
	function(accumulator, id)
		return loadObject(id)
			.andThen(function(object)
				accumulator[id] = object
				return accumulator
			end)
	end,
	{}
).expect()
```

---

# Timing

## Delay a value

```lua
local result = Promily.delay(1, "ready").expect()
```

## Sleep

```lua
Promily.sleep(.25).expect()
```

## Run work later

```lua
Promily.after(.5, function()
	return refreshInterface()
end)
```

## Delay an existing Promise's settlement

```lua
request()
	.delay(.25)
	.andThen(showResult)
```

---

# Timeouts

## Reject after timeout

```lua
local profile = loadProfile()
	.timeout(5)
	.expect()
```

## Custom timeout reason

```lua
loadProfile()
	.timeout(5, {
		reason = {
			kind = "Timeout",
			operation = "ProfileLoad",
		},
	})
```

## Fallback instead of rejection

```lua
local profile = loadProfile()
	.timeoutOr(2, cachedProfile)
	.expect()
```

## Static timeout

```lua
local profile = Promily.timeout(
	loadProfile(),
	5
).expect()
```

---

# Retries

## Basic retry

```lua
local value = Promily.retry(function()
	return requestServer()
end).expect()
```

Default attempts: `3`.

## Exponential backoff

```lua
local value = Promily.retry(function(attempt)
	print("attempt", attempt)

	return requestServer()
end, {
	attempts = 5,
	delaySeconds = .25,
	backoff = 2,
	maximumDelay = 4,
}).expect()
```

## Add jitter

```lua
Promily.retry(requestServer, {
	attempts = 5,
	delaySeconds = .5,
	backoff = 2,
	jitter = .2,
})
```

## Retry only transient failures

```lua
Promily.retry(function()
	return requestServer()
end, {
	attempts = 5,

	shouldRetry = function(reason, attempt)
		if attempt >= 5 then return false end
		if type(reason) ~= "table" then return false end

		return reason.kind == "Temporary"
	end,
})
```

---

# Roblox Events

## Wait for the next event

```lua
local arguments = Promily.fromEvent(button.Activated).expect()
```

## Wait for a specific event payload

```lua
local arguments = Promily.fromEvent(remote.OnClientEvent, {
	predicate = function(messageType)
		return messageType == "Loaded"
	end,
}).expect()
```

## Event timeout

```lua
local arguments = Promily.fromEvent(remote.OnClientEvent, {
	timeoutSeconds = 5,
	timeoutReason = "Server did not respond.",
}).expect()
```

## Multiple event values

```lua
local arguments = Promily.fromEvent(bindable.Event).expect()

local first = arguments[1]
local second = arguments[2]
```

The returned table is packed, so `arguments.n` is available.

---

# Roblox Attributes

## Wait until an Attribute exists

```lua
local token = Promily.fromAttribute<<string>>(
	model,
	"token"
).expect()
```

## Wait for a specific Attribute state

```lua
local ready = Promily.fromAttribute<<boolean>>(
	model,
	"ready",
	{
		predicate = function(value)
			return value == true
		end,
	}
).expect()
```

## Attribute timeout

```lua
local value = Promily.fromAttribute<<number>>(
	model,
	"itemId",
	{
		timeoutSeconds = 3,
	}
).expect()
```

---

# Roblox Properties

## Wait until a property reaches a target

```lua
local transparency = Promily.fromProperty<<number>>(
	part,
	"Transparency",
	{
		predicate = function(value)
			return value >= 1
		end,
	}
).expect()
```

## Wait until UI becomes visible

```lua
Promily.fromProperty<<boolean>>(
	frame,
	"Visible",
	{
		predicate = function(value)
			return value
		end,
	}
)
```

---

# Waiting for Children

## Direct child

```lua
local remote = Promily.fromChild(
	folder,
	"request",
	{
		className = "RemoteEvent",
		timeoutSeconds = 5,
	}
).expect()
```

## Recursive descendant

```lua
local target = Promily.fromChild(
	rootFolder,
	"Target",
	{
		recursive = true,
		timeoutSeconds = 5,
	}
).expect()
```

Promily checks existing objects once before subscribing for future additions.

---

# UI Lifecycle

Cancellation scopes work very well for UI pages/editors.

```lua
local pageScope: Promily.scope? = nil

local function openPage()
	if pageScope then return end

	pageScope = Promily.createScope()

	pageScope.track(loadPageData())
	pageScope.track(loadPreview())
	pageScope.track(loadIcons())
end

local function closePage()
	local scope = pageScope
	if not scope then return end

	pageScope = nil
	scope.delete()
end
```

No work from that scope should continue after the page closes.

---

# Remote Requests

A common Roblox pattern is wrapping a request id + response event.

```lua
local function requestProfile(userId: number): Promily.promise<any>
	return Promily.new(function(resolve, reject, onCancel)
		local requestId = HttpService:GenerateGUID(false)

		local connection = responseRemote.OnClientEvent:Connect(function(
			responseRequestId,
			success,
			data
		)
			if responseRequestId ~= requestId then return end

			connection:Disconnect()

			if success then
				resolve(data)
				return
			end

			reject(data)
		end)

		onCancel(function(_reason)
			connection:Disconnect()
		end)

		requestRemote:FireServer(requestId, userId)
	end)
		.timeout(5)
end
```

Then:

```lua
requestProfile(player.UserId)
	.retry -- not a method; use Promily.retry around request factory
```

Correct retry form:

```lua
Promily.retry(function()
	return requestProfile(player.UserId)
end, {
	attempts = 3,
	delaySeconds = .5,
})
```

---

# Data Loading

## Load several systems together

```lua
local loaded = Promily.props({
	profile = loadProfile(),
	settings = loadSettings(),
	inventory = loadInventory(),
	permissions = loadPermissions(),
}).expect()
```

## Continue with derived setup

```lua
Promily.props({
	profile = loadProfile(),
	settings = loadSettings(),
})
	.andThen(function(data)
		return initializeUI(data.profile, data.settings)
	end)
```

---

# Caching

## Cache-first fallback

```lua
readCache()
	.catch(function()
		return requestNetwork()
	end)
```

## Network-first with cache fallback

```lua
requestNetwork()
	.timeout(2)
	.catch(function()
		return readCache()
	end)
```

## First successful source

```lua
local value = Promily.any({
	readMemoryCache(),
	readPersistentCache(),
	requestNetwork(),
}).expect()
```

---

# Fallback Chains

```lua
primaryRequest()
	.catch(function()
		return secondaryRequest()
	end)
	.catch(function()
		return cachedValue
	end)
```

You can also use explicit values:

```lua
primaryRequest()
	.catchReturn(defaultValue)
```

---

# Loading Screens

```lua
showLoading()

Promily.props({
	profile = loadProfile(),
	assets = preloadAssets(),
	settings = loadSettings(),
})
	.andThen(function(data)
		renderApplication(data)
	end)
	.catch(function(reason)
		showLoadError(reason)
	end)
	.finally(function()
		hideLoading()
	end)
```

---

# Debounce-like Promise Work

Promily is not a polling/debounce framework, but cancellation scopes make one-shot replacement easy.

```lua
local searchScope: Promily.scope? = nil

local function search(query: string)
	if searchScope then
		searchScope.delete()
	end

	searchScope = Promily.createScope()
	local scope = searchScope

	scope.track(
		Promily.after(.2, function()
			return requestSearch(query)
		end)
	)
		.andThen(function(results)
			if scope.isDeleted() then return end

			renderResults(results)
		end)
end
```

Each new query cancels the previous pending delay/request chain owned by that scope.

---

# Result Objects

## Inspect without yielding

```lua
local result = promise.inspect()

print(result.status)
print(result.isSettled)
print(result.label)
print(result.value)
print(result.reason)
```

## Await structured result

```lua
local result = promise.awaitResult()
```

## Convert rejection/cancellation into resolved result data

```lua
local result = request()
	.toResult()
	.expect()

if result.status == Promily.status.resolved then
	useValue(result.value)
	return
end

warn(result.reason)
```

---

# Debugging

## Label Promise work

```lua
local request = loadProfile()
	.label(`profile:{player.UserId}`)
```

## Read id and label

```lua
print(request.getId())
print(request.getLabel())
```

## Custom unhandled rejection reporter

```lua
Promily.setUnhandledRejectionHandler(function(promiseValue, reason)
	warn(
		"[Promise Error]",
		promiseValue.getId(),
		promiseValue.getLabel(),
		reason
	)
end)
```

---

# Cleanup Patterns

## Event ownership

```lua
local promise = Promily.new(function(resolve, _reject, onCancel)
	local connection = event:Connect(resolve)

	onCancel(function(_reason)
		connection:Disconnect()
	end)
end)
```

## Timer ownership

```lua
local promise = Promily.new(function(resolve, _reject, onCancel)
	local timer = task.delay(1, resolve, "done")

	onCancel(function(_reason)
		task.cancel(timer)
	end)
end)
```

## Multiple resources

```lua
local promise = Promily.new(function(resolve, _reject, onCancel)
	local firstConnection = firstEvent:Connect(function()
	end)

	local secondConnection = secondEvent:Connect(function()
	end)

	local timer = task.delay(5, function()
		resolve(true)
	end)

	onCancel(function(_reason)
		firstConnection:Disconnect()
		secondConnection:Disconnect()
		task.cancel(timer)
	end)
end)
```

## `finally` for consumer cleanup

```lua
request()
	.finally(function()
		loadingFrame.Visible = false
	end)
```

Use executor `onCancel` for resources owned **inside** the operation. Use `finally()` for consumer-side cleanup after any settlement.

---

# Common Anti-Patterns

## Do not turn polling into a Promise

Avoid:

```lua
Promily.new(function(resolve)
	while not ready do
		task.wait()
	end

	resolve()
end)
```

Prefer an event/Attribute/property adapter:

```lua
Promily.fromAttribute<<boolean>>(
	model,
	"ready",
	{
		predicate = function(value)
			return value == true
		end,
	}
)
```

## Do not forget rejection handling

Avoid creating terminal rejected Promises that no owner handles.

```lua
request()
```

Prefer:

```lua
request()
	.catch(handleError)
```

or:

```lua
scope.track(request())
```

> `scope.track()` is lifecycle tracking only. It intentionally does **not** count as rejection handling, so still attach a `catch()` if rejection is expected.

## Do not cancel caller-owned inputs accidentally

Collection helpers intentionally do not cancel their input Promises.

If the collection should own them, use a scope:

```lua
local scope = Promily.createScope()

local requests = {
	scope.track(requestA()),
	scope.track(requestB()),
	scope.track(requestC()),
}

local aggregate = Promily.all(requests)

aggregate.finally(function()
	scope.delete()
end)
```

## Do not use Promise chains for permanent streams

Promises represent one eventual settlement.

For repeated values, use an event/signal abstraction instead.

Good Promise use:

```text
request
load
save
wait until
timeout
retry
one event
one transition
one completion
```

Not ideal:

```text
permanent event stream
continuous animation loop
frame updates
long-lived observable state
```

---

# Larger Example: Page Controller

```lua
local pageScope: Promily.scope? = nil

local function loadPage(): Promily.promise<any>
	return Promily.props({
		profile = Promily.retry(loadProfile, {
			attempts = 3,
			delaySeconds = .5,
			backoff = 2,
		}),

		settings = loadSettings(),

		assets = Promily.map(
			assetIds,
			loadAsset,
			{
				concurrency = 4,
			}
		),
	})
end

local function openPage()
	if pageScope then return end

	local scope = Promily.createScope()
	pageScope = scope

	showLoading()

	scope.track(loadPage())
		.andThen(function(data)
			if scope.isDeleted() then return end

			renderPage(data)
		end)
		.catch(function(reason)
			if scope.isDeleted() then return end

			showError(reason)
		end)
		.finally(function()
			if scope.isDeleted() then return end

			hideLoading()
		end)
end

local function closePage()
	local scope = pageScope
	if not scope then return end

	pageScope = nil
	scope.delete()
	destroyPage()
end
```

---

# Larger Example: Request/Response Remote

```lua
local function requestServer<T>(
	action: string,
	payload: any
): Promily.promise<T>
	return Promily.new(function(resolve, reject, onCancel)
		local requestId = HttpService:GenerateGUID(false)

		local connection = responseRemote.OnClientEvent:Connect(function(
			incomingRequestId,
			success,
			result
		)
			if incomingRequestId ~= requestId then return end

			connection:Disconnect()

			if success then
				resolve(result)
				return
			end

			reject(result)
		end)

		onCancel(function(_reason)
			connection:Disconnect()
		end)

		requestRemote:FireServer(requestId, action, payload)
	end)
		.timeout(5, {
			reason = {
				kind = "Timeout",
				action = action,
			},
		})
end
```

Usage:

```lua
Promily.retry(function()
	return requestServer("LoadProfile", {
		userId = player.UserId,
	})
end, {
	attempts = 3,
	delaySeconds = .5,
	backoff = 2,

	shouldRetry = function(reason)
		if type(reason) ~= "table" then return false end

		return reason.kind == "Timeout"
	end,
})
	.andThen(function(profile)
		useProfile(profile)
	end)
	.catch(function(reason)
		warn("Profile request failed:", reason)
	end)
```

---

# Larger Example: Startup Pipeline

```lua
Promily.sequence({
	function()
		return initializeData()
	end,

	function()
		return Promily.props({
			profile = loadProfile(),
			settings = loadSettings(),
		})
	end,

	function()
		return preloadAssets()
	end,

	function()
		return startInterface()
	end,
})
	.andThen(function()
		print("Startup complete")
	end)
	.catch(function(reason)
		warn("Startup failed:", reason)
	end)
```

---

# Quick Reference

```lua
-- creation
Promily.new(...)
Promily.resolve(...)
Promily.reject(...)
Promily.cancelled(...)
Promily.never(...)
Promily.try(...)
Promily.defer(...)
Promily.wrap(...)

-- cancellation
Promily.createCancellationSource()
Promily.createScope()

-- collection
Promily.all(...)
Promily.allSettled(...)
Promily.race(...)
Promily.any(...)
Promily.some(...)
Promily.props(...)
Promily.propsSettled(...)
Promily.map(...)
Promily.mapSettled(...)
Promily.filter(...)
Promily.find(...)
Promily.partition(...)
Promily.each(...)
Promily.sequence(...)
Promily.firstResolved(...)
Promily.reduce(...)

-- timing
Promily.delay(...)
Promily.sleep(...)
Promily.rejectAfter(...)
Promily.after(...)
Promily.timeout(...)
Promily.timeoutOr(...)
Promily.retry(...)

-- Roblox
Promily.fromEvent(...)
Promily.fromProperty(...)
Promily.fromAttribute(...)
Promily.fromChild(...)

-- promise
promise.andThen(...)
promise.catch(...)
promise.catchCancel(...)
promise.catchCancelReturn(...)
promise.finally(...)
promise.fork(...)
promise.tap(...)
promise.tapCancel(...)
promise.tapError(...)
promise.tapSettled(...)
promise.andThenReturn(...)
promise.catchReturn(...)
promise.cancel(...)
promise.delay(...)
promise.timeout(...)
promise.timeoutOr(...)
promise.withCancellation(...)
promise.await(...)
promise.awaitStatus(...)
promise.awaitResult(...)
promise.expect(...)
promise.observe(...)
promise.observeSettled(...)
promise.toResult(...)
promise.inspect(...)
promise.label(...)
promise.getId(...)
promise.getLabel(...)
promise.getStatus(...)
promise.isPending()
promise.isResolved()
promise.isRejected()
promise.isCancelled()
promise.isSettled()
```

---

## Detailed `Promily.*` API

### `Promily.getVersion`

Returns the current Promily package version.

#### Signature

```lua
Promily.getVersion(): string
```

#### Parameters

_No parameters._

#### Returns

A `string`.

#### Usage

```lua
local version = Promily.getVersion()
```

### `Promily.new`

Creates a new Promise and runs the executor in a one-shot spawned task.

#### Signature

```lua
Promily.new<T>(
	executor: (
		resolve: (value: T | promise<T>) -> (),
		reject: (reason: any) -> (),
		onCancel: (callback: (reason: any?) -> ()) -> boolean
	) -> (),
	token: cancellationToken?
): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `executor` | `(
		resolve: (value: T | promise<T>) -> (),
		reject: (reason: any) -> (),
		onCancel: (callback: (reason: any?) -> ()) -> boolean
	) -> (),
	token: cancellationToken?` | No | Promise executor. Receives `resolve`, `reject`, and `onCancel`. |

#### Returns

`promise<T>`.

#### Usage

```lua
local promise = Promily.new(function(resolve, reject, onCancel)
	local timer = task.delay(1, function()
		resolve("done")
	end)

	onCancel(function(_reason)
		task.cancel(timer)
	end)
end)
```

### `Promily.defer`

Creates an externally controlled deferred Promise with resolve/reject/cancel functions.

#### Signature

```lua
Promily.defer<T>(token: cancellationToken?): deferred<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `token` | `cancellationToken?` | No | Optional read-only Promily cancellation token. |

#### Returns

`deferred<T>`.

#### Usage

```lua
local deferred = Promily.defer<<number>>()
deferred.resolve(25)

local value = deferred.promise.expect()
```

### `Promily.resolve`

Returns a resolved Promise, or returns the supplied Promily Promise directly.

#### Signature

```lua
Promily.resolve<T>(value: T | promise<T>): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `T | promise<T>` | Yes | Value or Promise supplied to the operation. |

#### Returns

`promise<T>`.

#### Usage

```lua
local promise = Promily.resolve(10)
```

### `Promily.reject`

Creates an immediately rejected Promise.

#### Signature

```lua
Promily.reject<T>(reason: any): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `reason` | `any` | Yes | Rejection or cancellation reason. May be any Luau value. |

#### Returns

`promise<T>`.

#### Usage

```lua
local promise = Promily.reject("failed")
```

### `Promily.cancelled`

Creates an immediately cancelled Promise.

#### Signature

```lua
Promily.cancelled<T>(reason: any?): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `reason` | `any?` | No | Rejection or cancellation reason. May be any Luau value. |

#### Returns

`promise<T>`.

#### Usage

```lua
local promise = Promily.cancelled("owner closed")
```

### `Promily.never`

Creates a Promise that remains pending until explicitly cancelled or cancelled by its token.

#### Signature

```lua
Promily.never<T>(token: cancellationToken?): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `token` | `cancellationToken?` | No | Optional read-only Promily cancellation token. |

#### Returns

`promise<T>`.

#### Usage

```lua
local source = Promily.createCancellationSource()
local promise = Promily.never(source.getToken())

source.cancel("stop")
```

### `Promily.try`

Executes a callback and converts thrown errors into Promise rejection.

#### Signature

```lua
Promily.try<T>(
	callback: () -> (T | promise<T>),
	token: cancellationToken?
): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `() -> (T | promise<T>),
	token: cancellationToken?` | No | Callback invoked by Promily for this operation. |

#### Returns

`promise<T>`.

#### Usage

```lua
local promise = Promily.try(function()
	return riskyOperation()
end)
```

### `Promily.wrap`

Wraps a function so every call returns a Promily Promise.

#### Signature

```lua
Promily.wrap(
	callback: (...any) -> any
): (...any) -> promise<any>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(...any) -> any` | Yes | Callback invoked by Promily for this operation. |

#### Returns

`(...any) -> promise<any>`.

#### Usage

```lua
local asyncDouble = Promily.wrap(function(value: number)
	return value * 2
end)

local result = asyncDouble(5).expect()
```

### `Promily.is`

Returns whether a value is a Promily Promise.

#### Signature

```lua
Promily.is(value: any): boolean
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `any` | Yes | Value or Promise supplied to the operation. |

#### Returns

A `boolean`.

#### Usage

```lua
if Promily.is(value) then
	print("Promily Promise")
end
```

### `Promily.setUnhandledRejectionHandler`

Replaces Promily's global terminal unhandled-rejection reporter.

#### Signature

```lua
Promily.setUnhandledRejectionHandler(
	callback: (promiseValue: promise<any>, reason: any) -> ()
)
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(promiseValue: promise<any>, reason: any) -> ()` | Yes | Callback invoked by Promily for this operation. |

#### Returns

No return value.

#### Usage

```lua
Promily.setUnhandledRejectionHandler(function(promiseValue, reason)
	warn(promiseValue.getId(), promiseValue.getLabel(), reason)
end)
```

### `Promily.createCancellationSource`

Creates a mutable cancellation source and read-only token pair.

#### Signature

```lua
Promily.createCancellationSource(): cancellationSource
```

#### Parameters

_No parameters._

#### Returns

A mutable Promily cancellation source.

#### Usage

```lua
local source = Promily.createCancellationSource()
local token = source.getToken()

source.cancel("controller closed")
```

### `Promily.createScope`

Creates a lifecycle owner for tracking and cancelling a group of Promises.

#### Signature

```lua
Promily.createScope(): scope
```

#### Parameters

_No parameters._

#### Returns

A Promily cancellation scope.

#### Usage

```lua
local scope = Promily.createScope()

scope.track(loadProfile())
scope.track(loadSettings())

scope.delete()
```

### `Promily.all`

Resolves when all inputs resolve, preserving array order.

#### Signature

```lua
Promily.all<T>(values: {T | promise<T>}): promise<{T}>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{T | promise<T>}` | Yes | Input array or dictionary of values/Promises. |

#### Returns

`promise<{T}>`.

#### Usage

```lua
local results = Promily.all({
	loadProfile(),
	loadSettings(),
}).expect()
```

### `Promily.allSettled`

Resolves after every input settles and returns structured settlement records.

#### Signature

```lua
Promily.allSettled<T>(
	values: {T | promise<T>}
): promise<{settledResult<T>}>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{T | promise<T>}` | Yes | Input array or dictionary of values/Promises. |

#### Returns

`promise<{settledResult<T>}>`.

#### Usage

```lua
local results = Promily.allSettled({
	loadA(),
	loadB(),
}).expect()
```

### `Promily.race`

Settles from the first input to settle.

#### Signature

```lua
Promily.race<T>(values: {T | promise<T>}): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{T | promise<T>}` | Yes | Input array or dictionary of values/Promises. |

#### Returns

`promise<T>`.

#### Usage

```lua
local value = Promily.race({
	readCache(),
	requestNetwork(),
}).expect()
```

### `Promily.any`

Resolves from the first successful input; rejects with aggregate reasons if all fail.

#### Signature

```lua
Promily.any<T>(values: {T | promise<T>}): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{T | promise<T>}` | Yes | Input array or dictionary of values/Promises. |

#### Returns

`promise<T>`.

#### Usage

```lua
local value = Promily.any({
	readMemoryCache(),
	readDiskCache(),
	requestNetwork(),
}).expect()
```

### `Promily.some`

Resolves after the requested number of successful inputs.

#### Signature

```lua
Promily.some<T>(
	values: {T | promise<T>},
	count: number
): promise<{T}>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{T | promise<T>}` | Yes | Input array or dictionary of values/Promises. |
| `count` | `number` | Yes | Number of successful inputs required. |

#### Returns

`promise<{T}>`.

#### Usage

```lua
local fastestTwo = Promily.some({
	serverA(),
	serverB(),
	serverC(),
}, 2).expect()
```

### `Promily.props`

Resolves a keyed dictionary of values/Promises while preserving keys.

#### Signature

```lua
Promily.props<T>(
	values: {[string]: T | promise<T>}
): promise<{[string]: T}>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{[string]: T | promise<T>}` | Yes | Input array or dictionary of values/Promises. |

#### Returns

`promise<{[string]: T}>`.

#### Usage

```lua
local data = Promily.props({
	profile = loadProfile(),
	settings = loadSettings(),
}).expect()
```

### `Promily.map`

Maps an array asynchronously with optional concurrency limiting.

#### Signature

```lua
Promily.map<T, R>(
	values: {T},
	mapper: (value: T, index: number) -> (R | promise<R>),
	options: mapOptions?
): promise<{R}>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{T}` | Yes | Input array or dictionary of values/Promises. |
| `mapper` | `(value: T, index: number) -> (R | promise<R>),
	options: mapOptions?` | No | Function mapping each input value and index to a value or Promise. |

#### Returns

`promise<{R}>`.

#### Usage

```lua
local results = Promily.map(
	assetIds,
	function(assetId)
		return loadAsset(assetId)
	end,
	{
		concurrency = 4,
	}
).expect()
```

### `Promily.each`

Runs async work across an array and resolves with the original values.

#### Signature

```lua
Promily.each<T>(
	values: {T},
	callback: (value: T, index: number) -> (any | promise<any>),
	options: mapOptions?
): promise<{T}>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{T}` | Yes | Input array or dictionary of values/Promises. |
| `callback` | `(value: T, index: number) -> (any | promise<any>),
	options: mapOptions?` | No | Callback invoked by Promily for this operation. |

#### Returns

`promise<{T}>`.

#### Usage

```lua
local players = Promily.each(
	activePlayers,
	savePlayer,
	{
		concurrency = 3,
	}
).expect()
```

### `Promily.sequence`

Runs task factories sequentially and returns their ordered results.

#### Signature

```lua
Promily.sequence<R>(
	tasks: {() -> (R | promise<R>)}
): promise<{R}>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `tasks` | `{() -> (R | promise<R>)}` | Yes | Ordered task factories. Each task may return a value or Promise. |

#### Returns

`promise<{R}>`.

#### Usage

```lua
local results = Promily.sequence({
	initializeData,
	loadProfile,
	startInterface,
}).expect()
```

### `Promily.reduce`

Reduces an array sequentially where each reducer step may return a Promise.

#### Signature

```lua
Promily.reduce<T, R>(
	values: {T},
	reducer: (accumulator: R, value: T, index: number) -> (R | promise<R>),
	initialValue: R
): promise<R>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `values` | `{T}` | Yes | Input array or dictionary of values/Promises. |
| `reducer` | `(accumulator: R, value: T, index: number) -> (R | promise<R>),
	initialValue: R` | Yes | Async-compatible reducer function. |

#### Returns

`promise<R>`.

#### Usage

```lua
local total = Promily.reduce(
	{1, 2, 3},
	function(accumulator, value)
		return accumulator + value
	end,
	0
).expect()
```

### `Promily.delay`

Resolves with an optional value after a one-shot delay.

#### Signature

```lua
Promily.delay<T>(seconds: number, value: T?): promise<T?>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `seconds` | `number` | Yes | Delay or timeout duration in seconds. Must be non-negative. |
| `value` | `T?` | No | Value or Promise supplied to the operation. |

#### Returns

`promise<T?>`.

#### Usage

```lua
local value = Promily.delay(1, "ready").expect()
```

### `Promily.sleep`

Resolves after a one-shot delay with `nil`.

#### Signature

```lua
Promily.sleep(seconds: number): promise<nil>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `seconds` | `number` | Yes | Delay or timeout duration in seconds. Must be non-negative. |

#### Returns

`promise<nil>`.

#### Usage

```lua
Promily.sleep(.25).expect()
```

### `Promily.timeout`

Wraps a value/Promise with a timeout policy.

#### Signature

```lua
Promily.timeout<T>(
	source: T | promise<T>,
	seconds: number,
	options: timeoutOptions?
): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `T | promise<T>` | Yes | Value or Promise used as the source for the operation. |
| `seconds` | `number` | Yes | Delay or timeout duration in seconds. Must be non-negative. |
| `options` | `timeoutOptions?` | No | Optional typed configuration table for this operation. |

#### Returns

`promise<T>`.

#### Usage

```lua
local value = Promily.timeout(request(), 5).expect()
```

### `Promily.timeoutOr`

Returns a fallback value/Promise when the timeout expires.

#### Signature

```lua
Promily.timeoutOr<T, R>(
	source: T | promise<T>,
	seconds: number,
	fallback: R | promise<R>
): promise<T | R>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `T | promise<T>` | Yes | Value or Promise used as the source for the operation. |
| `seconds` | `number` | Yes | Delay or timeout duration in seconds. Must be non-negative. |
| `fallback` | `R | promise<R>` | Yes | Fallback value or Promise used when the timeout expires. |

#### Returns

`promise<T | R>`.

#### Usage

```lua
local value = Promily.timeoutOr(request(), 2, cachedValue).expect()
```

### `Promily.retry`

Retries a Promise-producing callback with optional delay, backoff, jitter, and retry predicate.

#### Signature

```lua
Promily.retry<T>(
	callback: (attempt: number) -> (T | promise<T>),
	options: retryOptions?
): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(attempt: number) -> (T | promise<T>),
	options: retryOptions?` | No | Callback invoked by Promily for this operation. |

#### Returns

`promise<T>`.

#### Usage

```lua
local value = Promily.retry(function(attempt)
	return requestServer(attempt)
end, {
	attempts = 5,
	delaySeconds = .25,
	backoff = 2,
	jitter = .15,
}).expect()
```

### `Promily.after`

Runs a callback after a one-shot delay and adopts its returned value/Promise.

#### Signature

```lua
Promily.after<T>(
	seconds: number,
	callback: () -> (T | promise<T>)
): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `seconds` | `number` | Yes | Delay or timeout duration in seconds. Must be non-negative. |
| `callback` | `() -> (T | promise<T>)` | Yes | Callback invoked by Promily for this operation. |

#### Returns

`promise<T>`.

#### Usage

```lua
local value = Promily.after(.5, function()
	return refreshData()
end).expect()
```

### `Promily.fromEvent`

Resolves from the next accepted Roblox signal emission.

#### Signature

```lua
Promily.fromEvent(
	signal: RBXScriptSignal,
	options: eventOptions?
): promise<{any}>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `signal` | `RBXScriptSignal` | Yes | Roblox signal to observe once. |
| `options` | `eventOptions?` | No | Optional typed configuration table for this operation. |

#### Returns

`promise<{any}>`.

#### Usage

```lua
local arguments = Promily.fromEvent(button.Activated, {
	timeoutSeconds = 10,
}).expect()
```

### `Promily.fromProperty`

Reads a Roblox property once, then waits on its property-changed signal until accepted.

#### Signature

```lua
Promily.fromProperty<T>(
	instance: Instance,
	propertyName: string,
	options: valueOptions<T>?
): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `instance` | `Instance` | Yes | Roblox Instance whose state is observed. |
| `propertyName` | `string` | Yes | Roblox property name to observe. |
| `options` | `valueOptions<T>?` | No | Optional typed configuration table for this operation. |

#### Returns

`promise<T>`.

#### Usage

```lua
local value = Promily.fromProperty<<number>>(
	part,
	"Transparency",
	{
		predicate = function(current)
			return current >= 1
		end,
	}
).expect()
```

### `Promily.fromAttribute`

Reads a Roblox Attribute once, then waits on its Attribute-changed signal until accepted.

#### Signature

```lua
Promily.fromAttribute<T>(
	instance: Instance,
	attributeName: string,
	options: valueOptions<T>?
): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `instance` | `Instance` | Yes | Roblox Instance whose state is observed. |
| `attributeName` | `string` | Yes | Roblox Attribute name to inspect. |
| `options` | `valueOptions<T>?` | No | Optional typed configuration table for this operation. |

#### Returns

`promise<T>`.

#### Usage

```lua
local ready = Promily.fromAttribute<<boolean>>(
	model,
	"ready",
	{
		predicate = function(value)
			return value == true
		end,
	}
).expect()
```

### `Promily.fromChild`

Finds an existing matching child/descendant or waits for one event-driven.

#### Signature

```lua
Promily.fromChild(
	parent: Instance,
	name: string,
	options: childOptions?
): promise<Instance>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `parent` | `Instance` | Yes | Roblox Instance under which Promily searches for the child. |
| `name` | `string` | Yes | Child name, debug label, counter name, or requested identifier depending on the API. |
| `options` | `childOptions?` | No | Optional typed configuration table for this operation. |

#### Returns

`promise<Instance>`.

#### Usage

```lua
local remote = Promily.fromChild(
	folder,
	"request",
	{
		className = "RemoteEvent",
		timeoutSeconds = 5,
	}
).expect()
```

---

## Detailed `promise.*` API

### `promise.andThen`

Creates a chained Promise. Returned Promises are adopted automatically; missing handlers forward the original settlement.

#### Signature

```lua
promise.andThen<R>(
	onResolved: ((value: T) -> (R | promise<R>))?,
	onRejected: ((reason: any) -> (R | promise<R>))?
): promise<R>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `onResolved` | `((value: T) -> (R | promise<R>))?` | No | Value supplied as `onResolved` for this operation. |
| `onRejected` | `((reason: any) -> (R | promise<R>))?` | No | Value supplied as `onRejected` for this operation. |

#### Usage

```lua
local nextPromise = promise.andThen(function(value)
	return transform(value)
end)
```

### `promise.andThenReturn`

QoL helper that ignores the resolved input and returns/adopts the supplied value.

#### Signature

```lua
promise.andThenReturn<R>(value: R | promise<R>): promise<R>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `R | promise<R>` | Yes | Value or Promise supplied to the operation. |

#### Usage

```lua
local nextPromise = promise.andThenReturn("done")
```

### `promise.await`

Yields until settlement and returns `true, value` only for resolution; otherwise `false, reason`.

#### Signature

```lua
promise.await(): (boolean, any?)
```

#### Parameters

_No parameters._

#### Usage

```lua
local success, valueOrReason = promise.await()
```

### `promise.awaitResult`

Yields until settlement and returns a structured result record.

#### Signature

```lua
promise.awaitResult(): promiseResult<T>
```

#### Parameters

_No parameters._

#### Usage

```lua
local result = promise.awaitResult()
```

### `promise.awaitStatus`

Yields until settlement and returns the exact status plus value/reason.

#### Signature

```lua
promise.awaitStatus(): (promiseStatus, any?)
```

#### Parameters

_No parameters._

#### Usage

```lua
local status, valueOrReason = promise.awaitStatus()
```

### `promise.cancel`

Cancels a pending Promise and runs its owned cancellation cleanup exactly once.

#### Signature

```lua
promise.cancel(reason: any?): boolean
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `reason` | `any?` | No | Rejection or cancellation reason. May be any Luau value. |

#### Usage

```lua
promise.cancel("page closed")
```

### `promise.catch`

Handles a rejection and optionally recovers with a value or Promise.

#### Signature

```lua
promise.catch<R>(onRejected: (reason: any) -> (R | promise<R>)): promise<T | R>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `onRejected` | `(reason: any) -> (R | promise<R>)` | Yes | Value supplied as `onRejected` for this operation. |

#### Usage

```lua
promise.catch(function(reason)
	warn(reason)
	return fallbackValue
end)
```

### `promise.catchReturn`

QoL rejection recovery helper that returns/adopts a fixed fallback.

#### Signature

```lua
promise.catchReturn<R>(value: R | promise<R>): promise<T | R>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `R | promise<R>` | Yes | Value or Promise supplied to the operation. |

#### Usage

```lua
local recovered = promise.catchReturn(defaultValue)
```

### `promise.delay`

Delays propagation of this Promise's settlement using one owned timer.

#### Signature

```lua
promise.delay(seconds: number): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `seconds` | `number` | Yes | Delay or timeout duration in seconds. Must be non-negative. |

#### Usage

```lua
local delayed = promise.delay(.25)
```

### `promise.expect`

Yields for settlement and returns the resolved value; rejects/cancellation become a thrown error.

#### Signature

```lua
promise.expect(message: string?): T
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `message` | `string?` | No | Value supplied as `message` for this operation. |

#### Usage

```lua
local value = promise.expect("Profile load failed")
```

### `promise.finally`

Runs cleanup after any settlement. If cleanup returns a Promise, Promily waits for it before preserving the original settlement.

#### Signature

```lua
promise.finally(callback: () -> any): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `() -> any` | Yes | Callback invoked by Promily for this operation. |

#### Usage

```lua
promise.finally(function()
	hideLoading()
end)
```

### `promise.getId`

Returns this Promise's internal debug id.

#### Signature

```lua
promise.getId(): number
```

#### Parameters

_No parameters._

#### Usage

```lua
print(promise.getId())
```

### `promise.getLabel`

Returns the optional debug label.

#### Signature

```lua
promise.getLabel(): string?
```

#### Parameters

_No parameters._

#### Usage

```lua
print(promise.getLabel())
```

### `promise.getStatus`

Returns the current Promise status without yielding.

#### Signature

```lua
promise.getStatus(): promiseStatus
```

#### Parameters

_No parameters._

#### Usage

```lua
local status = promise.getStatus()
```

### `promise.inspect`

Returns a non-yielding structured snapshot of this Promise.

#### Signature

```lua
promise.inspect(): promiseResult<T>
```

#### Parameters

_No parameters._

#### Usage

```lua
local result = promise.inspect()
```

### `promise.isCancelled`

Returns whether the Promise is cancelled.

#### Signature

```lua
promise.isCancelled(): boolean
```

#### Parameters

_No parameters._

#### Usage

```lua
if promise.isCancelled() then return end
```

### `promise.isPending`

Returns whether the Promise is still pending.

#### Signature

```lua
promise.isPending(): boolean
```

#### Parameters

_No parameters._

#### Usage

```lua
if promise.isPending() then print("waiting") end
```

### `promise.isRejected`

Returns whether the Promise rejected.

#### Signature

```lua
promise.isRejected(): boolean
```

#### Parameters

_No parameters._

#### Usage

```lua
print(promise.isRejected())
```

### `promise.isResolved`

Returns whether the Promise resolved.

#### Signature

```lua
promise.isResolved(): boolean
```

#### Parameters

_No parameters._

#### Usage

```lua
print(promise.isResolved())
```

### `promise.isSettled`

Returns whether the Promise is no longer pending.

#### Signature

```lua
promise.isSettled(): boolean
```

#### Parameters

_No parameters._

#### Usage

```lua
if promise.isSettled() then print("complete") end
```

### `promise.label`

Assigns a non-empty debug label and returns the same Promise.

#### Signature

```lua
promise.label(name: string): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `name` | `string` | Yes | Child name, debug label, counter name, or requested identifier depending on the API. |

#### Usage

```lua
local request = loadProfile().label("profile-load")
```

### `promise.observe`

Subscribes to one settlement without creating a chained Promise. A rejection callback marks the rejection handled.

#### Signature

```lua
promise.observe(
	onResolved: ((value: T) -> ())?,
	onRejected: ((reason: any) -> ())?,
	onCancelled: ((reason: any?) -> ())?
): observer<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `onResolved` | `((value: T) -> ())?` | No | Value supplied as `onResolved` for this operation. |
| `onRejected` | `((reason: any) -> ())?` | No | Value supplied as `onRejected` for this operation. |
| `onCancelled` | `((reason: any?) -> ())?` | No | Value supplied as `onCancelled` for this operation. |

#### Usage

```lua
local observer = promise.observe(
	print,
	warn,
	function(reason)
		print("cancelled", reason)
	end
)
```

### `promise.observeSettled`

Observes any settlement with a result object without marking rejection handled. Useful for lifecycle tracking.

#### Signature

```lua
promise.observeSettled(callback: (resultValue: promiseResult<T>) -> ()): observer<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(resultValue: promiseResult<T>) -> ()` | Yes | Callback invoked by Promily for this operation. |

#### Usage

```lua
promise.observeSettled(function(result)
	print(result.status)
end)
```

### `promise.tap`

Runs a success-side effect while preserving the resolved value.

#### Signature

```lua
promise.tap(callback: (value: T) -> any): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(value: T) -> any` | Yes | Callback invoked by Promily for this operation. |

#### Usage

```lua
promise.tap(function(value)
	print(value)
end)
```

### `promise.tapError`

Runs a rejection-side effect while preserving the rejection unless the tap itself fails.

#### Signature

```lua
promise.tapError(callback: (reason: any) -> any): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(reason: any) -> any` | Yes | Callback invoked by Promily for this operation. |

#### Usage

```lua
promise.tapError(function(reason)
	logError(reason)
end)
```

### `promise.timeout`

Creates a child Promise that rejects or resolves with a configured fallback when the timeout expires.

#### Signature

```lua
promise.timeout(seconds: number, options: timeoutOptions?): promise<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `seconds` | `number` | Yes | Delay or timeout duration in seconds. Must be non-negative. |
| `options` | `timeoutOptions?` | No | Optional typed configuration table for this operation. |

#### Usage

```lua
local value = promise.timeout(5).expect()
```

### `promise.timeoutOr`

QoL timeout helper that resolves/adopts the fallback instead of rejecting.

#### Signature

```lua
promise.timeoutOr<R>(seconds: number, fallback: R | promise<R>): promise<T | R>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `seconds` | `number` | Yes | Delay or timeout duration in seconds. Must be non-negative. |
| `fallback` | `R | promise<R>` | Yes | Fallback value or Promise used when the timeout expires. |

#### Usage

```lua
local value = promise.timeoutOr(2, cachedValue).expect()
```

### `promise.toResult`

Converts resolution/rejection/cancellation into a resolved structured result Promise.

#### Signature

```lua
promise.toResult(): promise<promiseResult<T>>
```

#### Parameters

_No parameters._

#### Usage

```lua
local result = request().toResult().expect()
```

---

## Deferred API

Created with:

```lua
local deferred = Promily.defer<<T>>()
```

### `deferred.promise`

```lua
deferred.promise: promise<T>
```

The owned Promise.

### `deferred.resolve`

```lua
deferred.resolve(value: T | promise<T>): boolean
```

Resolves or adopts the supplied Promise. Returns `false` after the deferred has already settled.

### `deferred.reject`

```lua
deferred.reject(reason: any): boolean
```

Rejects the deferred Promise.

### `deferred.cancel`

```lua
deferred.cancel(reason: any?): boolean
```

Cancels the deferred Promise.

---

## Cancellation Source and Token API

Create:

```lua
local source = Promily.createCancellationSource()
local token = source.getToken()
```

### Source methods

```lua
source.cancel(reason: any?): boolean
source.delete(): boolean
source.getToken(): cancellationToken
source.isCancelled(): boolean
source.isDeleted(): boolean
```

`source.cancel()` settles cancellation exactly once and asynchronously notifies current token listeners.

`source.delete()` disconnects retained cancellation listeners and closes the source. Deleting a source does not invent a cancellation reason; call `cancel()` first when cancellation semantics are required.

### Token methods

```lua
token.getReason(): any?
token.isCancelled(): boolean
token.onCancelled(callback: (reason: any?) -> ()): connection
token.throwIfCancelled(message: string?)
```

Example:

```lua
token.throwIfCancelled("Controller is no longer active.")
```

---

## Scope API

Create:

```lua
local scope = Promily.createScope()
```

### `scope.track`

```lua
scope.track<T>(promiseValue: promise<T>): promise<T>
```

Tracks one Promise until it settles. Tracking is rejection-neutral.

### `scope.newPromise`

```lua
scope.newPromise<T>(
	executor: (
		resolve: (value: T | promise<T>) -> (),
		reject: (reason: any) -> (),
		onCancel: (callback: (reason: any?) -> ()) -> boolean
	) -> ()
): promise<T>
```

Creates and tracks a Promise using the scope token.

### Remaining scope methods

```lua
scope.cancel(reason: any?): boolean
scope.delete(): boolean
scope.getCount(): number
scope.getToken(): cancellationToken
scope.isCancelled(): boolean
scope.isDeleted(): boolean
```

`scope.delete()` cancels tracked work with `"Promily scope deleted."`, deletes the underlying cancellation source, and clears tracking.

---

## Observer API

Both `promise.observe()` and `promise.observeSettled()` return:

```lua
type observer<T> = {
	connected: boolean,
	disconnect: () -> boolean,
}
```

Disconnecting prevents future delivery when the observer has not already dispatched.

Promily signal-style cancellation listener connections expose the same shape:

```lua
type connection = {
	connected: boolean,
	disconnect: () -> boolean,
}
```

---

## Status and Result Types

### Promise status

```lua
type promiseStatus =
	"Cancelled"
	| "Pending"
	| "Rejected"
	| "Resolved"
```

Runtime constants:

```lua
Promily.status.pending
Promily.status.resolved
Promily.status.rejected
Promily.status.cancelled
```

### Promise result

```lua
type promiseResult<T> = {
	id: number,
	isSettled: boolean,
	label: string?,
	reason: any?,
	status: promiseStatus,
	value: T?,
}
```

### Settled collection result

```lua
type settledResult<T> = {
	reason: any?,
	status: promiseStatus,
	value: T?,
}
```

---

## Option Types

### `mapOptions`

```lua
type mapOptions = {
	concurrency: number?,
}
```

`concurrency` must be at least `1`. Omitted means all inputs may begin immediately.

### `timeoutOptions`

```lua
type timeoutOptions = {
	fallback: any?,
	hasFallback: boolean?,
	reason: any?,
}
```

For normal fallback behavior, prefer:

```lua
promise.timeoutOr(seconds, fallback)
Promily.timeoutOr(source, seconds, fallback)
```

### `retryOptions`

```lua
type retryOptions = {
	attempts: number?,
	backoff: number?,
	delaySeconds: number?,
	jitter: number?,
	maximumDelay: number?,
	shouldRetry: ((reason: any, attempt: number) -> boolean)?,
}
```

Defaults:

| Option | Default |
| --- | ---: |
| `attempts` | `3` |
| `backoff` | `1` |
| `delaySeconds` | `0` |
| `jitter` | `0` |
| `maximumDelay` | `nil` |
| `shouldRetry` | `nil` |

### `eventOptions`

```lua
type eventOptions = {
	predicate: ((...any) -> boolean)?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}
```

### `valueOptions<T>`

```lua
type valueOptions<T> = {
	predicate: ((value: T) -> boolean)?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}
```

### `childOptions`

```lua
type childOptions = {
	className: string?,
	recursive: boolean?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}
```

---

## Module Responsibilities

Responsibilities:

| Module | Responsibility |
| --- | --- |
| `src/init.luau` | Public package API |
| `src/core/promise.luau` | Promise state machine, chaining, deadlines, diagnostics, awaiting, inspection |
| `src/core/cancellation.luau` | Cancellation source/token |
| `src/core/errors.luau` | Shared structured error contracts |
| `src/core/scope.luau` | Group Promise ownership |
| `src/combinators/collection.luau` | Arrays/dictionaries, map, sequence, reduce |
| `src/combinators/control.luau` | Delay, timeout, retry |
| `src/concurrency/queue.luau` | Persistent bounded async work queue |
| `src/concurrency/semaphore.luau` | Shared permit/concurrency control |
| `src/concurrency/singleFlight.luau` | Concurrent request deduplication |
| `src/adapters/roblox.luau` | Roblox event/property/Attribute/child adapters |

---

## Testing

Promily ships with a dependency-free Roblox test suite.

Use `test.project.json` to mount:

```text
ReplicatedStorage
└── Promily

ServerScriptService
└── PromilyTests
```

The current 62 tests cover core chaining, rejection recovery, `finally`, cancellation cleanup, tokens, scopes, combinators, concurrency limiting, timeouts, retry, Roblox adapters, wrapping, and result conversion.

Before publishing a release, run the Studio test runner and require zero failures.

---

## Performance and Lifecycle

> Package: `Promily`
> Version: `1.2.5`
> Entry point: `src/init.luau`

## Summary

Promily was built as a Lily-owned Promise implementation for Roblox Luau with no runtime third-party packages.

| Check | Result |
| --- | ---: |
| Source ModuleScripts | 11 |
| Test Luau files | 2 |
| Public `Promily.*` functions | 46 |
| Promise instance methods | 36 |
| Source lines | 5,273 |
| Test lines | 1,171 |
| Runtime dependencies | 0 |
| `--!strict` Luau files | 13/13 |
| Duplicate public functions | 0 |
| Prohibited-pattern findings | 0 |

## Lily Static Checks

The source/test scan found:

- no `pairs()` or `ipairs()`
- no `else` or `elseif`
- no recurring/polling `while` or `repeat` loops; the only `while` is the bounded Promise-adoption cycle walk
- no `task.wait()`
- no `RenderStepped`
- no `Stepped`
- no permanent `Heartbeat`
- no polling loop
- no third-party package dependency
- no generated line-count padding
- no numbered filler registries

One-shot scheduling is intentionally used where scheduling is the feature:

- `task.spawn()` for Promise executor startup and coroutine resumption
- `task.defer()` for Promise observer delivery and immediate cancellation callbacks
- `task.delay()` for delay/timeout/retry timers
- `task.cancel()` for owned timer cleanup

## Ownership / Cleanup Checks

Promily explicitly owns cleanup for:

- Promise observers
- cancellation listeners
- cancellation cleanup callbacks
- adopted Promise observers
- chained parent observers
- `finally()` cleanup observers
- `toResult()` source observers
- timeout timers
- delayed-settlement timers
- retry timers
- retry active attempts
- Roblox event connections
- Roblox property-change connections
- Roblox Attribute-change connections
- Roblox child/descendant connections
- cancellation scope tracking

Collection combinators detach aggregate observers when they settle/cancel.

Collection combinators intentionally do **not** cancel caller-owned input Promises merely because the aggregate settles early. Use `Promily.createScope()` when aggregate input operations should have one explicit cancellation owner.

## Cancellation Semantics

- Promise cancellation is terminal.
- parent cancellation propagates to chained children.
- child cancellation detaches from its parent instead of silently cancelling caller-owned parent work.
- cancellation cleanup callbacks receive the cancellation reason.
- cancellation tokens are read-only; cancellation sources own mutation.
- cancellation scopes can cancel tracked Promise groups.
- `Promily.retry()` cancels its active retry attempt when the retry owner is cancelled.

## Unhandled Rejections

Rejected terminal Promises schedule a one-shot unhandled-rejection check.

- attaching a rejection observer handles that rejection.
- rejection forwarding moves responsibility to the downstream Promise.
- `observeSettled()` is intentionally rejection-neutral.
- `toResult()` intentionally converts/handles rejection.
- the global rejection reporter is protected with `pcall()`.

## Roblox Adapter Model

Roblox adapters are event-driven.

- `fromProperty()` subscribes first and then rechecks, preventing a lost-change race.
- `fromAttribute()` subscribes first and then rechecks, preventing a lost-change race.
- `fromChild()` subscribes before scanning the existing hierarchy, preventing a lost-child race.
- `fromEvent()` connects only to the supplied signal.
- adapter timeout work is one-shot and is cancelled on settlement/cancellation.

## Test Coverage Included

`tests/spec.luau` covers:

- resolve + chaining
- rejection recovery
- finally preservation
- cancellation cleanup
- cancellation source/token
- cancellation scope
- all
- allSettled
- any
- some
- props
- concurrency-limited map
- sequential execution
- async reduce
- timeout
- timeout fallback
- retry
- event adapter
- Attribute adapter
- property adapter
- child adapter
- wrap
- result conversion
- Promise adoption locking and indirect cycle rejection
- observer failure isolation
- cancellation listeners
- absolute deadlines
- pending-Promise diagnostics
- queue concurrency, close/drain, clear, and idle behavior
- semaphore permits, cancellation, and `use()`
- single-flight deduplication and consumer cancellation isolation
- cancellation recovery and cancellation-side taps
- independent Promise forks and token-bound consumer branches
- settled mapping and keyed settled props
- asynchronous filter/find/partition helpers
- lazy first-success fallback tasks
- delayed rejection timers
- invalid concurrency/property handling

## Environment Limitation

This build environment does not contain Roblox Studio, `luau`, `luau-analyze`, or `stylua`.

Therefore this audit verifies package structure, API consistency, lifecycle design, static source rules, and source-level invariants, but it does **not** claim that the Roblox runtime test suite was executed here.

Before publishing `1.2.5`, run the included Rojo test project in Roblox Studio and require that `ServerScriptService/PromilyTests/run.server.luau` completes with zero failures.

## Release Gate

Recommended release gate:

```text
static Promily audit
    ↓
Rojo sync
    ↓
Roblox Studio typecheck
    ↓
PromilyTests: 0 failures
    ↓
publish/tag v1.2.5
```

---

## Literal Full API Index

### Everything after `Promily.`

```lua
Promily.getVersion
Promily.new
Promily.defer
Promily.resolve
Promily.reject
Promily.cancelled
Promily.never
Promily.try
Promily.wrap
Promily.is
Promily.setUnhandledRejectionHandler
Promily.createCancellationSource
Promily.createScope
Promily.createQueue
Promily.createSemaphore
Promily.createSingleFlight
Promily.fork
Promily.withCancellation
Promily.all
Promily.allSettled
Promily.race
Promily.any
Promily.some
Promily.props
Promily.propsSettled
Promily.map
Promily.mapSettled
Promily.filter
Promily.find
Promily.partition
Promily.each
Promily.sequence
Promily.firstResolved
Promily.reduce
Promily.delay
Promily.sleep
Promily.rejectAfter
Promily.timeout
Promily.timeoutOr
Promily.deadline
Promily.retry
Promily.after
Promily.fromEvent
Promily.fromProperty
Promily.fromAttribute
Promily.fromChild
Promily.diagnostics
Promily.status
```

### Everything on a Promise

```lua
promise.andThen
promise.andThenReturn
promise.await
promise.awaitResult
promise.awaitStatus
promise.cancel
promise.catch
promise.catchCancel
promise.catchCancelReturn
promise.catchReturn
promise.deadline
promise.delay
promise.expect
promise.finally
promise.fork
promise.getId
promise.getLabel
promise.getStatus
promise.inspect
promise.isCancelled
promise.isPending
promise.isRejected
promise.isResolved
promise.isSettled
promise.label
promise.onCancel
promise.observe
promise.observeSettled
promise.tap
promise.tapCancel
promise.tapError
promise.tapSettled
promise.timeout
promise.timeoutOr
promise.toResult
promise.withCancellation
```

### Deferred

```lua
deferred.promise
deferred.resolve
deferred.reject
deferred.cancel
```

### Cancellation source

```lua
source.cancel
source.delete
source.getToken
source.isCancelled
source.isDeleted
```

### Cancellation token

```lua
token.getReason
token.isCancelled
token.onCancelled
token.throwIfCancelled
```

### Scope

```lua
scope.cancel
scope.delete
scope.getCount
scope.getToken
scope.isCancelled
scope.isDeleted
scope.newPromise
scope.track
```

### Observer / connection

```lua
observer.connected
observer.disconnect

connection.connected
connection.disconnect
```

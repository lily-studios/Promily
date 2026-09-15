--!strict

-- runs queued asynchronous jobs with bounded concurrency and explicit lifecycle ownership

local module = {}

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")

local errors = require(core:WaitForChild("errors"))
local promiseModule = require(core:WaitForChild("promise"))

--————————————————————————————————————————————————————————————————————--

export type queueOptions = {
	concurrency: number?,
	maxPending: number?,
}

export type queue = {
	clear: (reason: any?) -> number,
	close: () -> boolean,
	delete: (reason: any?) -> boolean,
	getActiveCount: () -> number,
	getPendingCount: () -> number,
	isClosed: () -> boolean,
	isDeleted: () -> boolean,
	onIdle: () -> promiseModule.promise<nil>,
	push: <T>(callback: () -> T | promiseModule.promise<T>) -> promiseModule.promise<T>,
}

type job = {
	callback: () -> any,
	deferredValue: promiseModule.deferred<any>,
}

--————————————————————————————————————————————————————————————————————--

local function isPositiveInteger(value: number): boolean
	if value ~= value then
		return false
	end

	if value >= math.huge then
		return false
	end

	if value < 1 then
		return false
	end

	if value % 1 ~= 0 then
		return false
	end

	return true
end

--————————————————————————————————————————————————————————————————————--

--- Creates a bounded asynchronous work queue.
---@param options queueOptions? Queue concurrency and pending-capacity options.
---@return queue queueValue New queue.
function module.new(options: queueOptions?): queue
	local concurrency = 1
	local maxPending: number? = nil

	if options then
		if options.concurrency ~= nil then
			concurrency = options.concurrency
		end

		maxPending = options.maxPending
	end

	assert(
		isPositiveInteger(concurrency),
		"Promily queue concurrency must be a positive integer."
	)

	if maxPending ~= nil then
		assert(
			maxPending == maxPending,
			"Promily queue maxPending must be a finite non-negative integer."
		)

		assert(
			maxPending < math.huge,
			"Promily queue maxPending must be a finite non-negative integer."
		)

		assert(
			maxPending >= 0,
			"Promily queue maxPending must be a finite non-negative integer."
		)

		assert(
			maxPending % 1 == 0,
			"Promily queue maxPending must be a finite non-negative integer."
		)
	end

	local activeCount = 0
	local activeJobs: {[job]: boolean} = {}
	local idleWaiters: {promiseModule.deferred<nil>} = {}
	local isClosedValue = false
	local isDeletedValue = false
	local jobs: {job} = {}

	local drain: () -> ()

	--————————————————————————————————————————————————————————————————————--

	local function resolveIdleWaiters()
		if activeCount ~= 0 then
			return
		end

		if #jobs ~= 0 then
			return
		end

		if #idleWaiters == 0 then
			return
		end

		local currentWaiters = idleWaiters
		idleWaiters = {}

		for _, waiter in currentWaiters do
			waiter.resolve(nil)
		end

		table.clear(currentWaiters)
	end

	--————————————————————————————————————————————————————————————————————--

	local function cancelIdleWaiters(reason: any?)
		if #idleWaiters == 0 then
			return
		end

		local currentWaiters = idleWaiters
		idleWaiters = {}

		for _, waiter in currentWaiters do
			waiter.cancel(reason)
		end

		table.clear(currentWaiters)
	end

	--————————————————————————————————————————————————————————————————————--

	local function finishJob(jobValue: job)
		activeJobs[jobValue] = nil
		activeCount -= 1

		assert(
			activeCount >= 0,
			"Promily queue active count became negative."
		)

		drain()
		resolveIdleWaiters()
	end

	--————————————————————————————————————————————————————————————————————--

	local function startJob(jobValue: job)
		if jobValue.deferredValue.promise.isSettled() then
			drain()
			resolveIdleWaiters()

			return
		end

		activeCount += 1
		activeJobs[jobValue] = true

		local source = promiseModule.try(jobValue.callback)
		local observerValue: promiseModule.observer<any>?

		observerValue = source.observe(
			function(value: any)
				if observerValue then
					observerValue.disconnect()
					observerValue = nil
				end

				jobValue.deferredValue.resolve(value)
				finishJob(jobValue)
			end,

			function(reason: any)
				if observerValue then
					observerValue.disconnect()
					observerValue = nil
				end

				jobValue.deferredValue.reject(reason)
				finishJob(jobValue)
			end,

			function(reason: any?)
				if observerValue then
					observerValue.disconnect()
					observerValue = nil
				end

				jobValue.deferredValue.cancel(reason)
				finishJob(jobValue)
			end
		)
	end

	--————————————————————————————————————————————————————————————————————--

	drain = function()
		local scanCount = #jobs

		for _ = 1, scanCount do
			if activeCount >= concurrency then
				break
			end

			local jobValue = table.remove(jobs, 1)

			if not jobValue then
				break
			end

			if jobValue.deferredValue.promise.isSettled() then
				continue
			end

			startJob(jobValue)
		end

		resolveIdleWaiters()
	end

	--————————————————————————————————————————————————————————————————————--

	--- Adds a lazy asynchronous job to the queue.
	---@generic T
	---@param callback fun(): T | promiseModule.promise<T> Lazy job callback.
	---@return promiseModule.promise<T> promiseValue Queued job Promise.
	local function push<T>(
		callback: () -> T | promiseModule.promise<T>
	): promiseModule.promise<T>
		if isDeletedValue then
			return promiseModule.reject(
				errors.queueDeleted("Promily queue is deleted.")
			)
		end

		if isClosedValue then
			return promiseModule.reject(errors.queueClosed())
		end

		if maxPending ~= nil and #jobs >= maxPending and activeCount >= concurrency then
			return promiseModule.reject(errors.queueFull(maxPending))
		end

		local deferredValue: promiseModule.deferred<T> = promiseModule.defer()

		local jobValue: job = {
			callback = callback :: any,
			deferredValue = deferredValue :: any,
		}

		jobs[#jobs + 1] = jobValue

		deferredValue.promise.onCancel(function()
			local index = table.find(jobs, jobValue)

			if not index then
				return
			end

			table.remove(jobs, index)
			resolveIdleWaiters()
		end)

		drain()

		return deferredValue.promise
	end

	--————————————————————————————————————————————————————————————————————--

	--- Cancels all queued jobs that have not started.
	---@param reason any? Cancellation reason.
	---@return number removedCount Number of queued jobs removed.
	local function clear(reason: any?): number
		if #jobs == 0 then
			return 0
		end

		local currentJobs = jobs
		jobs = {}

		local removed = #currentJobs

		for _, jobValue in currentJobs do
			jobValue.deferredValue.cancel(reason)
		end

		table.clear(currentJobs)
		resolveIdleWaiters()

		return removed
	end

	--————————————————————————————————————————————————————————————————————--

	--- Stops accepting new jobs while allowing accepted work to drain.
	---@return boolean closedValue Whether the queue transitioned to closed.
	local function close(): boolean
		if isDeletedValue then
			return false
		end

		if isClosedValue then
			return false
		end

		isClosedValue = true
		resolveIdleWaiters()

		return true
	end

	--————————————————————————————————————————————————————————————————————--

	--- Deletes the queue and cancels Promily-owned queued and active job wrappers.
	---@param reason any? Deletion reason.
	---@return boolean deletedValue Whether deletion occurred.
	local function delete(reason: any?): boolean
		if isDeletedValue then
			return false
		end

		isDeletedValue = true
		isClosedValue = true

		local deleteError = errors.queueDeleted(reason)

		clear(deleteError)

		for jobValue in activeJobs do
			jobValue.deferredValue.cancel(deleteError)
		end

		cancelIdleWaiters(deleteError)

		return true
	end

	--————————————————————————————————————————————————————————————————————--

	--- Returns the number of jobs currently executing.
	---@return number activeCountValue Active job count.
	local function getActiveCount(): number
		return activeCount
	end

	--————————————————————————————————————————————————————————————————————--

	--- Returns the number of jobs waiting to start.
	---@return number pendingCount Pending job count.
	local function getPendingCount(): number
		return #jobs
	end

	--————————————————————————————————————————————————————————————————————--

	--- Returns whether the queue is closed to new jobs.
	---@return boolean closedValue Whether the queue is closed.
	local function isClosed(): boolean
		return isClosedValue
	end

	--————————————————————————————————————————————————————————————————————--

	--- Returns whether the queue has been deleted.
	---@return boolean deletedValue Whether the queue is deleted.
	local function isDeleted(): boolean
		return isDeletedValue
	end

	--————————————————————————————————————————————————————————————————————--

	--- Resolves when the queue has no active or pending jobs.
	---@return promiseModule.promise<nil> promiseValue Idle Promise.
	local function onIdle(): promiseModule.promise<nil>
		if isDeletedValue then
			return promiseModule.reject(
				errors.queueDeleted("Promily queue is deleted.")
			)
		end

		if activeCount == 0 and #jobs == 0 then
			return promiseModule.resolve(nil)
		end

		local deferredValue: promiseModule.deferred<nil> = promiseModule.defer()

		idleWaiters[#idleWaiters + 1] = deferredValue

		deferredValue.promise.onCancel(function()
			local index = table.find(idleWaiters, deferredValue)

			if not index then
				return
			end

			table.remove(idleWaiters, index)
		end)

		return deferredValue.promise
	end

	--————————————————————————————————————————————————————————————————————--

	return {
		clear = clear,
		close = close,
		delete = delete,
		getActiveCount = getActiveCount,
		getPendingCount = getPendingCount,
		isClosed = isClosed,
		isDeleted = isDeleted,
		onIdle = onIdle,
		push = push,
	}
end

--————————————————————————————————————————————————————————————————————--

return module

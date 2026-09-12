--!strict

-- adapts Roblox signals, properties, attributes, and hierarchy changes into Promily promises

local module = {}

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")
local promiseModule = require(core:WaitForChild("promise"))

--————————————————————————————————————————————————————————————————————--

export type eventOptions = {
	predicate: ((...any) -> boolean)?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}

export type valueOptions<T> = {
	predicate: ((value: T) -> boolean)?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}

export type childOptions = {
	className: string?,
	recursive: boolean?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}

--————————————————————————————————————————————————————————————————————--

local function createTimeout(
	seconds: number?,
	reason: any?,
	onTimeout: (reason: any) -> ()
): thread?
	if seconds == nil then return nil end

	assert(seconds >= 0, "Promily adapter timeout must be non-negative.")

	local timeoutReason = reason

	if timeoutReason == nil then
		timeoutReason = `Promily adapter timed out after {seconds} seconds.`
	end

	return task.delay(seconds, onTimeout, timeoutReason)
end

--————————————————————————————————————————————————————————————————————--

function module.fromEvent(
	signal: RBXScriptSignal,
	options: eventOptions?
): promiseModule.promise<{any}>
	return promiseModule.new(function(resolve, reject, onCancel)
		local connection: RBXScriptConnection?
		local timerThread: thread?
		local settled = false

		local function cleanup()
			local currentConnection = connection
			connection = nil

			if currentConnection then
				currentConnection:Disconnect()
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function onSignal(...: any)
			if settled then return end

			if options and options.predicate then
				local success, accepted = pcall(options.predicate :: any, ...)

				if not success then
					settled = true
					cleanup()
					reject(accepted)
					return
				end

				if not accepted then return end
			end

			settled = true
			cleanup()
			resolve(table.pack(...))
		end

		connection = signal:Connect(onSignal)

		if options then
			timerThread = createTimeout(
				options.timeoutSeconds,
				options.timeoutReason,
				function(reason)
					if settled then return end

					settled = true
					cleanup()
					reject(reason)
				end
			)
		end

		onCancel(function(_reason)
			settled = true
			cleanup()
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

function module.fromProperty<T>(
	instance: Instance,
	propertyName: string,
	options: valueOptions<T>?
): promiseModule.promise<T>
	return promiseModule.new(function(resolve, reject, onCancel)
		local target = instance :: any
		local connection: RBXScriptConnection?
		local timerThread: thread?
		local settled = false

		local function cleanup()
			local currentConnection = connection
			connection = nil

			if currentConnection then
				currentConnection:Disconnect()
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function testCurrent(): boolean
			local value = target[propertyName] :: T

			if options and options.predicate then
				local success, accepted = pcall(options.predicate, value)

				if not success then
					settled = true
					cleanup()
					reject(accepted)
					return true
				end

				if not accepted then return false end
			end

			settled = true
			cleanup()
			resolve(value)

			return true
		end

		if testCurrent() then return end

		connection = instance:GetPropertyChangedSignal(propertyName):Connect(function()
			if settled then return end

			testCurrent()
		end)

		if options then
			timerThread = createTimeout(
				options.timeoutSeconds,
				options.timeoutReason,
				function(reason)
					if settled then return end

					settled = true
					cleanup()
					reject(reason)
				end
			)
		end

		onCancel(function(_reason)
			settled = true
			cleanup()
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

function module.fromAttribute<T>(
	instance: Instance,
	attributeName: string,
	options: valueOptions<T>?
): promiseModule.promise<T>
	return promiseModule.new(function(resolve, reject, onCancel)
		local connection: RBXScriptConnection?
		local timerThread: thread?
		local settled = false

		local function cleanup()
			local currentConnection = connection
			connection = nil

			if currentConnection then
				currentConnection:Disconnect()
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function testCurrent(): boolean
			local currentValue = instance:GetAttribute(attributeName)
			if currentValue == nil then return false end

			local value = currentValue :: T

			if options and options.predicate then
				local success, accepted = pcall(options.predicate, value)

				if not success then
					settled = true
					cleanup()
					reject(accepted)
					return true
				end

				if not accepted then return false end
			end


			settled = true
			cleanup()
			resolve(value)

			return true
		end

		if testCurrent() then return end

		connection = instance:GetAttributeChangedSignal(attributeName):Connect(function()
			if settled then return end

			testCurrent()
		end)

		if options then
			timerThread = createTimeout(
				options.timeoutSeconds,
				options.timeoutReason,
				function(reason)
					if settled then return end

					settled = true
					cleanup()
					reject(reason)
				end
			)
		end

		onCancel(function(_reason)
			settled = true
			cleanup()
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

function module.fromChild(
	parent: Instance,
	name: string,
	options: childOptions?
): promiseModule.promise<Instance>
	assert(name ~= "", "Promily.fromChild() name cannot be empty.")

	local recursive = false
	local className: string? = nil

	if options then
		recursive = options.recursive == true
		className = options.className
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local connection: RBXScriptConnection?
		local timerThread: thread?
		local settled = false

		local function cleanup()
			local currentConnection = connection
			connection = nil

			if currentConnection then
				currentConnection:Disconnect()
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function matches(instance: Instance): boolean
			if instance.Name ~= name then return false end
			if className and not instance:IsA(className) then return false end

			return true
		end

		local function resolveIfMatch(instance: Instance): boolean
			if not matches(instance) then return false end

			settled = true
			cleanup()
			resolve(instance)

			return true
		end

		local existingObjects = parent:GetChildren()

		if recursive then
			existingObjects = parent:GetDescendants()
		end

		for _, instance in existingObjects do
			if not resolveIfMatch(instance) then continue end

			return
		end

		local signal = parent.ChildAdded

		if recursive then
			signal = parent.DescendantAdded
		end

		connection = signal:Connect(function(instance)
			if settled then return end

			resolveIfMatch(instance)
		end)

		if options then
			timerThread = createTimeout(
				options.timeoutSeconds,
				options.timeoutReason,
				function(reason)
					if settled then return end

					settled = true
					cleanup()
					reject(reason)
				end
			)
		end

		onCancel(function(_reason)
			settled = true
			cleanup()
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

return module

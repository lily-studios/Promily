# Reactily

> **Version:** `1.1.0`
> **Language:** Roblox Luau
> **Type mode:** `--!strict`
> **Lifecycle convention:** Reactily-owned resources use `.delete()` / `.isDeleted()`
> **Package entry point:** `src/init.luau`

Reactily is a Lily-owned, React-inspired interface framework for Roblox Luau. It combines typed Roblox UI creators, virtual elements, function components, hooks, keyed reconciliation, portals, standalone state, stores, signals, bindings, themes, styles, focus management, fixed and variable virtualization, TweenService animation, animation groups, idle-safe springs, transitions, context, memoization, forwarded refs, lazy components, Suspense/resources, error boundaries, profiling, bounded object pools, diagnostics, and an idle-safe scheduler.

This README is both the getting-started guide and the full supported reference for the public API exported from `src/init.luau`. It also documents returned objects, typed creators, prop types, composition patterns, lifecycle behavior, and the advanced modules used to implement the framework.

---

## Table of Contents

- [Overview](#overview)
- [Installation and Source Layout](#installation-and-source-layout)
- [Quick Start](#quick-start)
- [Core Conventions](#core-conventions)
- [Elements and Typed Creators](#elements-and-typed-creators)
- [Components](#components)
- [Roots and Rendering](#roots-and-rendering)
- [Fragments, Keys, and Portals](#fragments-keys-and-portals)
- [Refs, Attributes, Tags, and Events](#refs-attributes-tags-and-events)
- [Hooks](#hooks)
- [Atoms and Computed State](#atoms-and-computed-state)
- [History State](#history-state)
- [Stores and Selectors](#stores-and-selectors)
- [Bindings](#bindings)
- [Signals](#signals)
- [Themes and Styles](#themes-and-styles)
- [Animation](#animation)
- [Focus Groups](#focus-groups)
- [Virtual Lists](#virtual-lists)
- [Object Pools](#object-pools)
- [Scheduler](#scheduler)
- [Diagnostics](#diagnostics)
- [Lifecycle Ownership](#lifecycle-ownership)
- [Performance Model](#performance-model)
- [Reactily 1.1 Systems](#reactily-11-systems)
- [Using Systems Together](#using-systems-together)
- [Complete 1.1 Public API Index](#complete-11-public-api-index)
- [Public API Reference](#public-api-reference)
- [Returned Object APIs](#returned-object-apis)
- [Typed Creator Reference](#typed-creator-reference)
- [Typed Prop Reference](#typed-prop-reference)
- [Advanced Module Reference](#advanced-module-reference)
- [Complete Examples](#complete-examples)

---

## Overview

Reactily's public surface is dot-based:

```lua
local Reactily = require(path.Reactily)

local root = Reactily.createRoot(playerGui)
root.render(element)
root.delete()
```

Reactily-owned APIs do **not** use colon calls:

```lua
-- Correct
root.render(element)
store.set(nextState)
signal.fire(value)
animation.delete()

-- Incorrect for Reactily-owned APIs
root:render(element)
store:set(nextState)
signal:fire(value)
```

Roblox-owned APIs retain Roblox's required method syntax:

```lua
instance:Destroy()
connection:Disconnect()
instance:SetAttribute("enabled", true)
signal:Connect(callback)
```

---

## Installation

For source development with Git:

```bash
git clone https://github.com/lily-studios/Reactily.git
cd Reactily
```

Update an existing clone with:

```bash
git pull
```

For a packaged build, use the repository's GitHub Releases page and install the provided Roblox package/model when one is available. A source ZIP can also be downloaded from GitHub and mounted with the same `src/init.luau` entry point.

With Rojo, map Reactily into the location your project uses for shared packages, then serve your project normally.


Mount the package into Roblox with `src/init.luau` as the package entry point, then require the mounted package:

```lua
local Reactily = require(path.To.Reactily)
```

Check the runtime version:

```lua
print(Reactily.getVersion()) -- "1.1.0"
```

---

## Quick Start

```lua
local Reactily = require(path.Reactily)

local function counter(): Reactily.element
	local count, setCount = Reactily.useState(0)

	return Reactily.createTextButton({
		size = UDim2.fromOffset(240, 64),
		text = `Count: {count}`,
		textSize = 28,

		onActivated = function()
			setCount(function(previous: number): number
				return previous + 1
			end)
		end,
	})
end

local root = Reactily.createRoot(playerGui)

root.render(
	Reactily.createComponent(counter, {})
)
```

Delete the root when the interface is permanently removed:

```lua
root.delete()
```

---

## Core Conventions

### Dot-only Reactily APIs

Reactily objects are closure-backed records. Call their functions with `.`:

```lua
atom.set(1)
binding.delete()
root.suspend()
selector.get()
```

### `delete()` means Reactily lifecycle cleanup

Reactily uses `delete()` for framework-owned resource cleanup:

```lua
root.delete()
signal.delete()
store.delete()
theme.delete()
animation.delete()
```

Deletion functions generally return `true` when they perform deletion and `false` if the object was already deleted.

### Change-only updates

Atoms, stores, bindings, themes, hook state, reducer state, selectors, and host updates skip downstream work when the relevant value is unchanged.

```lua
local value = Reactily.createAtom(10)

print(value.set(10)) -- false
print(value.set(20)) -- true
```

> **Table state:** Luau table equality is reference equality. For state tables, represent a changed state with a new table instead of mutating the existing table and setting the same reference.

### Strict types and autocomplete

Typed creators use class-relevant props:

```lua
Reactily.createFrame({
	size = UDim2.fromScale(1, 1),
	backgroundTransparency = .2,
})
```

`createFrame()` receives `frameProps?`. `createTextButton()` receives `textButtonProps?`. This provides class-specific editor completion.

---

## Elements and Typed Creators

A Reactily element is virtual data. Creating an element does not immediately create a Roblox Instance. The root's renderer creates and updates Instances during reconciliation.

```lua
local element = Reactily.createFrame({
	name = "Panel",
	size = UDim2.fromOffset(400, 300),
	backgroundColor3 = Color3.fromRGB(28, 28, 32),
}, {
	Reactily.createTextLabel({
		size = UDim2.fromScale(1, 0),
		automaticSize = Enum.AutomaticSize.Y,
		text = "Reactily",
		textSize = 30,
	}),
})
```

Prefer a typed creator when Reactily exposes one:

```lua
-- Preferred
Reactily.createFrame({
	size = UDim2.fromOffset(200, 100),
})

-- Generic escape hatch
Reactily.createElement("Frame", {
	size = UDim2.fromOffset(200, 100),
})
```

`createElement()` accepts generic props and therefore does not provide the same class-specific autocomplete.

---

## Components

Define props with ordinary Luau types:

```lua
type panelProps = {
	title: string,
	visible: boolean,
}

local function panel(props: panelProps): Reactily.element
	return Reactily.createFrame({
		visible = props.visible,
	}, {
		Reactily.createTextLabel({
			text = props.title,
		}),
	})
end
```

Create the component element:

```lua
local element = Reactily.createComponent<panelProps>(
	panel,
	{
		title = "Effects",
		visible = true,
	}
)
```

Full signature:

```lua
Reactily.createComponent<P>(
	componentValue: Reactily.component<P>,
	props: P,
	children: {Reactily.element}?,
	key: string?
): Reactily.element
```

### Hook rules

Hooks must run only during component render and must retain the same order and completed-render count. Reactily checks hook kind, hook order, and completed-render hook count.

---

## Roots and Rendering

Create a root:

```lua
local root = Reactily.createRoot(playerGui)
```

Render:

```lua
root.render(element)
```

Unmount while keeping the root:

```lua
root.render(nil)
```

Delete the entire root runtime:

```lua
root.delete()
```

### Batching

```lua
root.batch(function()
	root.render(firstTree)
	root.render(finalTree)
end)
```

Nested batches are supported. The render occurs after the outermost batch completes.

### Suspension

```lua
root.suspend()
root.render(nextTree)
```

The new tree remains pending while suspended.

```lua
root.resume()
```

`resume()` renders pending work if needed.

### Manual flush

```lua
root.flush()
```

Flushes queued scheduler work owned by the root.

---

## Fragments, Keys, and Portals

### Fragments

```lua
local items = Reactily.createFragment({
	Reactily.createTextLabel({ text = "A" }),
	Reactily.createTextLabel({ text = "B" }),
})
```

Optional key:

```lua
Reactily.createFragment(children, "section")
```

### Keys

Host props expose `key`:

```lua
Reactily.createTextButton({
	key = `fixture-{fixtureId}`,
	text = tostring(fixtureId),
})
```

Use stable identity-based keys when children can move, be inserted, or be removed.

### Portals

```lua
local modal = Reactily.createPortal(overlayGui, {
	Reactily.createFrame({
		size = UDim2.fromScale(1, 1),
		backgroundTransparency = .35,
	}),
}, "modal")
```

Signature:

```lua
Reactily.createPortal(
	target: Instance,
	children: {Reactily.element},
	key: string?
): Reactily.element
```

---

## Refs, Attributes, Tags, and Events

### Refs

```lua
local buttonInstance: TextButton? = nil

Reactily.createTextButton({
	ref = function(instance: TextButton?)
		buttonInstance = instance
	end,
})
```

The ref receives the mounted host and later receives `nil` when the ref changes or the host is removed.

### Attributes

```lua
Reactily.createFrame({
	attributes = {
		panelType = "effects",
		fixtureId = 12,
		enabled = true,
	},
})
```

Supported values are documented under [`attributeValue`](#attributevalue).

### CollectionService tags

```lua
Reactily.createFrame({
	tags = {
		"[Lily] Interface",
		"[Lily] Panel",
	},
})
```

Reactily diffs the tags it manages for the host while preserving unrelated external tags.

### Events

```lua
Reactily.createTextButton({
	onActivated = function(input: InputObject, clickCount: number)
		print(input, clickCount)
	end,

	onMouseEnter = function()
		print("hover")
	end,
})
```

Changing an event callback disconnects the previous Reactily-owned event connection.

---

## Hooks

### `useState`

```lua
local value, setValue = Reactily.useState(initialValue)
```

```lua
Reactily.useState<T>(
	initialValue: T
): (
	T,
	(value: T | ((previous: T) -> T)) -> ()
)
```

The setter is stable across renders.

### `useReducer`

```lua
type state = {
	count: number,
}

type action =
	{type: "increment"}
	| {type: "reset"}

local current, dispatch = Reactily.useReducer<state, action>(
	function(previous: state, actionValue: action): state
		if actionValue.type == "increment" then
			return {
				count = previous.count + 1,
			}
		end

		return {
			count = 0,
		}
	end,
	{
		count = 0,
	}
)
```

### `useRef`

```lua
local dragging = Reactily.useRef(false)
dragging.current = true
```

Changing `.current` does not request a render.

### `useMemo`

```lua
local visibleFixtures = Reactily.useMemo(function()
	return calculateVisibleFixtures(fixtures, selection)
end, {fixtures, selection})
```

If dependencies are omitted, Reactily treats them as changed each render.

### `useCallback`

```lua
local onActivated = Reactily.useCallback(function()
	print(selection)
end, {selection})
```

### `useEffect`

```lua
Reactily.useEffect(function()
	local connection = instance.Changed:Connect(function()
		print("changed")
	end)

	return function()
		connection:Disconnect()
	end
end, {instance})
```

Effect cleanup runs before a changed effect and when the component context is deleted. If dependencies are omitted, the effect is treated as changed each render.

### `usePrevious`

```lua
local previous = Reactily.usePrevious(currentValue)
```

Returns `nil` on the first render.

### `useBoolean`

```lua
local enabled, enable, disable, toggle = Reactily.useBoolean(false)

enable()
disable()
toggle()
```

Return order:

```text
value, enable, disable, toggle
```

### `useToggle`

```lua
local open, toggle, setOpen = Reactily.useToggle(false)

toggle()
setOpen(true)
```

### `useCounter`

```lua
local count, controls = Reactily.useCounter(0)

controls.increment()
controls.increment(5)
controls.decrement()
controls.set(100)
controls.reset()
```

### `useDebouncedValue`

```lua
local query, setQuery = Reactily.useState("")
local debouncedQuery = Reactily.useDebouncedValue(query, .2)
```

The delayed task is cancelled when dependencies change or the owning effect is deleted.

### `useAttribute`

```lua
local enabled, setEnabled = Reactily.useAttribute(
	fixture,
	"enabled",
	true
)

setEnabled(false)
```

Synchronizes hook state with the Roblox Attribute.

---

## Atoms and Computed State

```lua
local bpm = Reactily.createAtom(.7)
```

Read:

```lua
local current = bpm.get()
```

Set:

```lua
local didChange = bpm.set(.8)
```

Update:

```lua
bpm.update(function(previous: number): number
	return previous + .1
end)
```

Subscribe:

```lua
local connection = bpm.subscribe(function(change)
	print(change.previous, change.current)
end)
```

Delete:

```lua
bpm.delete()
```

### Computed atoms

```lua
local percentage = Reactily.createComputed(
	intensity,
	function(value: number): string
		return `{math.round(value * 100)}%`
	end
)
```

The computed value owns its source subscription. `percentage.delete()` disconnects it.

### Attribute-backed atoms

```lua
local enabled = Reactily.createAttributeAtom(
	fixture,
	"enabled",
	true
)
```

State and Attribute changes synchronize both ways. Delete the atom when that synchronization scope ends.

---

## History State

```lua
local position = Reactily.createHistoryAtom(Vector2.zero, 100)
```

```lua
position.set(Vector2.new(100, 50))
position.undo()
position.redo()
```

Inspect history:

```lua
print(position.canUndo())
print(position.canRedo())
print(position.getPastCount())
print(position.getFutureCount())
```

Clear history without changing the current value:

```lua
position.clearHistory()
```

The `limit` applies to retained past entries.

---

## Stores and Selectors

```lua
type panelState = {
	page: string,
	selectedFixture: number?,
	bpm: number,
}

local store = Reactily.createStore<panelState>({
	page = "Home",
	selectedFixture = nil,
	bpm = .7,
})
```

Update:

```lua
store.update(function(previous: panelState): panelState
	return {
		page = "Effects",
		selectedFixture = previous.selectedFixture,
		bpm = previous.bpm,
	}
end)
```

### Selectors

```lua
local page = store.select(function(state: panelState): string
	return state.page
end)
```

```lua
page.subscribe(function(change)
	print(change.previous, change.current)
end)
```

Selectors emit only when the selected result changes.

Delete a selector manually:

```lua
page.delete()
```

Deleting the store also deletes its active selectors.

### Batching

```lua
store.batch(function()
	store.update(firstUpdate)
	store.update(secondUpdate)
end)
```

Nested batches are supported.

---

## Bindings

```lua
local intensity = Reactily.createBinding(.5)
```

Map:

```lua
local percent = Reactily.mapBinding(
	intensity,
	function(value: number): number
		return value * 100
	end
)
```

Combine:

```lua
local pan = Reactily.createBinding(0)
local tilt = Reactily.createBinding(0)

local position = Reactily.combineBindings(
	pan,
	tilt,
	function(panValue: number, tiltValue: number): Vector2
		return Vector2.new(panValue, tiltValue)
	end
)
```

Clamp:

```lua
local normalized = Reactily.clampBinding(intensity, 0, 1)
```

Round:

```lua
local rounded = Reactily.roundBinding(intensity, 2)
```

Format:

```lua
local label = Reactily.formatBinding(
	intensity,
	function(value: number): string
		return `{math.round(value * 100)}%`
	end
)
```

Derived bindings own their upstream subscriptions and disconnect them on `.delete()`.

---

## Signals

```lua
local selected = Reactily.createSignal<number>()
```

Connect:

```lua
local connection = selected.connect(function(fixtureId: number)
	print(fixtureId)
end)
```

Fire:

```lua
selected.fire(5)
```

Once:

```lua
selected.once(function(fixtureId: number)
	print("first:", fixtureId)
end)
```

Disconnect:

```lua
connection.disconnect()
```

Delete:

```lua
selected.delete()
```

### Operators

```lua
local mapped = Reactily.mapSignal(source, mapper)
local filtered = Reactily.filterSignal(source, predicate)
local distinct = Reactily.distinctSignal(source)
local merged = Reactily.mergeSignals({first, second})
local skipped = Reactily.skipSignal(source, 2)
local firstFive = Reactily.takeSignal(source, 5)
```

Derived signals own and release their upstream connections.

---

## Themes and Styles

### Themes

```lua
type themeTokens = {
	accent: Color3,
	background: Color3,
	text: Color3,
}

local theme = Reactily.createTheme<themeTokens>({
	accent = Color3.fromRGB(80, 120, 255),
	background = Color3.fromRGB(24, 24, 28),
	text = Color3.new(1, 1, 1),
})
```

```lua
theme.update(function(previous: themeTokens): themeTokens
	return {
		accent = Color3.fromRGB(255, 100, 120),
		background = previous.background,
		text = previous.text,
	}
end)
```

Resolve immediately:

```lua
local accent = Reactily.resolveTheme(
	theme,
	function(tokens: themeTokens): Color3
		return tokens.accent
	end
)
```

### Styles

```lua
local baseStyle: Reactily.style = {
	backgroundColor3 = Color3.fromRGB(30, 30, 35),
	borderSizePixel = 0,
}

local selectedStyle: Reactily.style = {
	backgroundColor3 = Color3.fromRGB(60, 90, 180),
}
```

Merge:

```lua
local styleValue = Reactily.createStyle({
	baseStyle,
	selectedStyle,
})
```

Apply:

```lua
local props = Reactily.applyStyle({
	size = UDim2.fromOffset(200, 80),
}, styleValue)

local button = Reactily.createTextButton(props)
```

---

## Animation

Create without playing:

```lua
local animation = Reactily.createTween(
	frame,
	{
		BackgroundTransparency = 0,
		Position = UDim2.fromScale(.5, .5),
	},
	{
		time = .2,
		easingStyle = Enum.EasingStyle.Quad,
		easingDirection = Enum.EasingDirection.Out,
	}
)
```

```lua
animation.play()
```

Create and play:

```lua
local animation = Reactily.playTween(frame, goals, {
	time = .2,
})
```

Completion:

```lua
animation.onCompleted(function(playbackState)
	print(playbackState)
end)
```

Delete:

```lua
animation.delete()
```

Deletion disconnects Reactily-owned completion listeners, cancels the Tween, and destroys the Roblox Tween internally.

---

## Focus Groups

```lua
local focusGroup = Reactily.createFocusGroup()

focusGroup.add(playButton)
focusGroup.add(settingsButton)

focusGroup.focusFirst()
focusGroup.focusLast()
```

```lua
focusGroup.remove(settingsButton)
focusGroup.clear()
focusGroup.delete()
```

Clear the current Roblox GUI selection:

```lua
Reactily.clearFocus()
```

A focus target must have a parent, be visible, and be selectable.

---

## Virtual Lists

```lua
local range = Reactily.resolveVirtualList(
	5000,
	44,
	scrollingFrame.CanvasPosition.Y,
	scrollingFrame.AbsoluteWindowSize.Y,
	3
)
```

Returned values:

```lua
print(range.first)
print(range.last)
print(range.offset)
print(range.totalSize)
```

Slice an array:

```lua
local visibleFixtures = Reactily.sliceVirtualList(fixtures, range)
```

When `itemCount == 0`, `first` and `last` are both `0`.

---

## Object Pools

### Instance pool

```lua
local pool = Reactily.createInstancePool("Frame", 64)

local frame = pool.acquire()
frame.Parent = playerGui

pool.release(frame)
```

When the retained pool is full, released Instances are destroyed instead of retained.

### Generic pool

```lua
type temporaryData = {
	value: number,
}

local pool = Reactily.createObjectPool<temporaryData>(
	function(): temporaryData
		return {
			value = 0,
		}
	end,
	function(object: temporaryData)
		object.value = 0
	end,
	function(_object: temporaryData)
		-- custom final deletion
	end,
	128
)
```

```lua
print(pool.getAvailableCount())
print(pool.getCreatedCount())
pool.delete()
```

---

## Scheduler

Reactily's scheduler uses a temporary `RunService.Heartbeat` connection only while queued work exists.

```lua
local scheduler = Reactily.createScheduler()
```

Queue:

```lua
local taskId = scheduler.enqueue(function()
	print("scheduled")
end)
```

Keyed queue:

```lua
scheduler.enqueueKeyed("layout", function()
	rebuildLayout()
end)
```

A second pending task with the same key updates the existing pending callback rather than stacking another keyed task.

Cancel:

```lua
scheduler.cancel(taskId)
scheduler.cancelKey("layout")
```

Flush:

```lua
scheduler.flush()
```

Clear:

```lua
scheduler.clear()
```

Delete:

```lua
scheduler.delete()
```

---

## Diagnostics

Diagnostics are explicit counters and do not poll.

```lua
local diagnostics = Reactily.createDiagnostics()

diagnostics.increment("renders")
diagnostics.increment("hostCreates", 5)

print(diagnostics.get("renders"))
print(diagnostics.snapshot())
```

```lua
diagnostics.reset("renders")
diagnostics.resetAll()
diagnostics.delete()
```

---

## Lifecycle Ownership

```lua
local owner = Reactily.createLifecycleOwner()
```

Public type:

```lua
type lifecycleOwner = {
	cleanups: {() -> ()},
	connections: {RBXScriptConnection},
	instances: {Instance},
	isDeleted: boolean,
}
```

Most application code should prefer higher-level Reactily objects that already own their resources.

### Deletion guide

| Object | Delete when |
| --- | --- |
| `root` | The rendered interface/root is permanently removed |
| `atom` | Standalone state is no longer used |
| `computed` | The derived state is no longer needed |
| `historyAtom` | The history state owner ends |
| `store` | The store/application scope ends |
| `selector` | The selector is no longer needed before its store ends |
| `binding` | The binding/derived binding scope ends |
| `signal` | The signal owner ends |
| `scheduler` | The scheduler owner ends |
| `objectPool` | The pool owner ends |
| `theme` | The theme owner ends |
| `focusGroup` | The focus scope ends |
| `animation` | The animation owner is no longer needed |
| `diagnostics` | The diagnostics scope ends |

---

## Performance Model

Reactily is event-driven and change-oriented.

### Scheduler dormancy

The scheduler:

1. Connects Heartbeat only when queued work exists.
2. Disconnects before flushing.
3. Reconnects only if callbacks queue more work.
4. Stops immediately when cancellation empties the queue.
5. Does not keep a permanent per-frame callback alive.

### Change-only state

Atoms, stores, bindings, themes, hook state, reducers, selectors, and host property updates avoid downstream work when values are unchanged.

### Derived ownership

Mapped/filtered/distinct/merged/take/skip signals and mapped/combined bindings disconnect upstream subscriptions on `.delete()`.

### Keyed reconciliation

Stable keys preserve child identity when list ordering changes.

```lua
for _, fixture in fixtures do
	children[#children + 1] = Reactily.createTextButton({
		key = tostring(fixture.id),
		text = fixture.name,
	})
end
```

### Virtualization

For large fixed-height lists, render only `range.first` through `range.last`.

---


---

# Reactily 1.1 Systems

Reactily 1.1 keeps the original package model but expands the framework into a more complete UI runtime. Normal application code should still require only the package root:

```lua
local Reactily = require(path.To.Reactily)
```

The sections below explain what the newer systems do and how they fit with the existing API.

## Batching, comparison, and immutable updates

`Reactily.batch` groups compatible downstream notifications. `Reactily.shallowEqual` provides shallow equality, and `Reactily.patch` creates immutable shallow updates.

```lua
type state = {
	page: string,
	selectedId: number?,
}

local store = Reactily.createStore<state>({
	page = "Home",
	selectedId = nil,
})

Reactily.batch(function()
	store.update(function(previous: state): state
		return Reactily.patch(previous, {
			page = "Library",
		})
	end)

	store.update(function(previous: state): state
		return Reactily.patch(previous, {
			selectedId = 12,
		})
	end)
end)
```

These functions work especially well with stores, selectors, memoized components, and change-only state.

## Context

Contexts provide typed values to descendant components without manually threading the value through every component's props.

```lua
type themeValues = {
	primary: Color3,
	secondary: Color3,
}

local themeContext = Reactily.createContext<themeValues>({
	primary = Color3.new(1, 1, 1),
	secondary = Color3.fromRGB(128, 128, 128),
})

local function label(): Reactily.element
	local theme = Reactily.useContext(themeContext)

	return Reactily.createTextLabel({
		text = "Reactily",
		textColor3 = theme.primary,
		backgroundColor3 = theme.secondary,
	})
end

local tree = Reactily.createContextProvider(
	themeContext,
	{
		primary = Color3.fromRGB(120, 170, 255),
		secondary = Color3.fromRGB(30, 30, 35),
	},
	{
		Reactily.createComponent(label, {}),
	}
)
```

Use `createContext`, `createContextProvider`, and `useContext` together.

## Memoized components

`Reactily.memo` wraps a component and prevents unnecessary component work when its props compare equal.

```lua
type labelProps = {
	text: string,
}

local function label(props: labelProps): Reactily.element
	return Reactily.createTextLabel({
		text = props.text,
	})
end

local memoizedLabel = Reactily.memo(label)
```

Pass a custom comparator when shallow equality is not the right rule.

```lua
local memoizedLabel = Reactily.memo(
	label,
	function(previousProps, nextProps)
		return previousProps.text == nextProps.text
	end
)
```

Memoization works naturally with immutable state updates, selectors, and `Reactily.shallowEqual`.

## Forwarded refs and imperative handles

`Reactily.forwardRef` lets a component receive a forwarded ref. `useImperativeHandle` can expose a controlled imperative interface instead of the underlying implementation object.

```lua
type handle = {
	focus: () -> (),
}

local input = Reactily.forwardRef(function(props, ref)
	local objectRef = Reactily.useRef<TextBox?>(nil)

	Reactily.useImperativeHandle(ref, function(): handle
		return {
			focus = function()
				local object = objectRef.current
				if not object then return end

				object:CaptureFocus()
			end,
		}
	end, {})

	return Reactily.createTextBox({
		ref = objectRef,
		text = props.text,
	})
end)
```

## Lazy components

`Reactily.lazy` defers loading a component implementation until it is needed. `Reactily.preloadLazy` can start loading it earlier.

```lua
local settingsPanel = Reactily.lazy(function()
	return require(script.Parent.SettingsPanel)
end)

Reactily.preloadLazy(settingsPanel)

local element = Reactily.createComponent(settingsPanel, {})
```

Lazy components are designed to work with Suspense and error boundaries.

## Suspense and resources

`Reactily.createResource` creates asynchronous readable state, while `Reactily.createSuspense` provides a fallback boundary for descendants that suspend while data or code is pending.

```lua
local fallback = Reactily.createTextLabel({
	text = "Loading...",
})

local content = Reactily.createComponent(contentComponent, {})

local boundary = Reactily.createSuspense(
	fallback,
	content
)
```

A resource is created with a loader:

```lua
local resource = Reactily.createResource(function()
	return loadData()
end)
```

Use resources for asynchronous values that belong to Reactily's Suspense flow. Use lazy components for asynchronous component loading.

## Error boundaries

Error boundaries isolate render failures from the rest of the mounted tree.

```lua
local fallback = Reactily.createTextLabel({
	text = "Something went wrong.",
})

local safeTree = Reactily.createErrorBoundary(
	fallback,
	childElement,
	function(failure)
		warn(failure)
	end
)
```

Error boundaries compose with Suspense:

```lua
local safeAsyncTree = Reactily.createErrorBoundary(
	errorFallback,
	Reactily.createSuspense(
		loadingFallback,
		asyncChild
	)
)
```

Suspension represents pending work; an error boundary handles actual failure.

## Store selectors and combined stores

A selector tracks one derived value from a store.

```lua
local store = Reactily.createStore({
	page = "Home",
	count = 0,
})

local count = Reactily.createSelector(
	store,
	function(state)
		return state.count
	end
)
```

Multiple stores can be combined:

```lua
local first = Reactily.createStore({
	value = 10,
})

local second = Reactily.createStore({
	value = 20,
})

local total = Reactily.combineStores(
	{first, second},
	function(values)
		return values[1].value + values[2].value
	end
)
```

Selectors work with `useStore`, batching, immutable `patch` updates, and memoized components.

## Component store subscriptions

`useStore` subscribes a component to a full store or a selected value.

```lua
local function counterLabel(): Reactily.element
	local count = Reactily.useStore(
		store,
		function(state)
			return state.count
		end
	)

	return Reactily.createTextLabel({
		text = tostring(count),
	})
end
```

Only use the full state when the component genuinely needs the full state.

## Bindings and Roblox properties

Bindings can drive Roblox properties directly.

```lua
local position = Reactily.createBinding(
	UDim2.fromOffset(0, 0)
)

local cleanup = Reactily.bindProperty(
	position,
	frame,
	"Position",
	false
)

position.set(
	UDim2.fromOffset(100, 50)
)

cleanup()
position.delete()
```

Pass `true` as the final argument for two-way synchronization:

```lua
local cleanup = Reactily.bindProperty(
	position,
	frame,
	"Position",
	true
)
```

External Roblox property changes then update the source binding too.

## Bindings and Roblox Attributes

The same pattern works with Attributes:

```lua
local enabled = Reactily.createBinding(true)

local cleanup = Reactily.bindAttribute(
	enabled,
	instance,
	"Enabled",
	true
)
```

`bindProperty` and `bindAttribute` return cleanup callbacks. Call them when the binding relationship is no longer needed.

## Combining many bindings

`combineBindingsMany` derives one value from any number of bindings.

```lua
local firstBinding = Reactily.createBinding(0)
local secondBinding = Reactily.createBinding(0)
local thirdBinding = Reactily.createBinding(0)

local combinedBinding = Reactily.combineBindingsMany(
	{
		firstBinding,
		secondBinding,
		thirdBinding,
	},
	function(values)
		return values[1] + values[2] + values[3]
	end
)
```

Derived bindings clean up their upstream subscriptions when deleted.

## Springs

`createSpring` creates standalone owned spring state.

```lua
local spring = Reactily.createSpring(0, {
	frequency = 8,
	damping = 1,
})

spring.setTarget(1)
```

Inside components, prefer `useSpring` when the spring should share the component lifetime:

```lua
local function component(): Reactily.element
	local target, setTarget = Reactily.useState(0)
	local spring = Reactily.useSpring(target, {
		frequency = 8,
		damping = 1,
	})

	return Reactily.createFrame({})
end
```

Springs are idle-safe: continuous runtime work should exist only while a spring is actively settling.

## Animation composition

Tween animations and delay steps can be grouped into sequences or parallel animation groups.

```lua
local first = Reactily.createTween(
	firstFrame,
	{
		Position = UDim2.fromOffset(100, 0),
	},
	{
		time = .2,
	}
)

local delay = Reactily.createAnimationDelay(.1)

local second = Reactily.createTween(
	secondFrame,
	{
		Position = UDim2.fromOffset(100, 0),
	},
	{
		time = .2,
	}
)

local sequence = Reactily.sequenceAnimations({
	first,
	delay,
	second,
})

sequence.play()
```

Parallel groups start their children together:

```lua
local group = Reactily.parallelAnimations({
	firstAnimation,
	secondAnimation,
})

group.play()
```

## Transitions and deferred values

Transitions schedule low-priority one-shot work.

```lua
Reactily.startTransition(function()
	store.update(function(previous)
		return Reactily.patch(previous, {
			page = "Results",
		})
	end)
end)
```

Inside a component:

```lua
local function component(): Reactily.element
	local query, setQuery = Reactily.useState("")
	local isPending, startTransition = Reactily.useTransition()
	local deferredQuery = Reactily.useDeferredValue(query)

	return Reactily.createTextLabel({
		text = if isPending
			then "Updating..."
			else deferredQuery,
	})
end
```

Use transitions for work that may be deferred without blocking direct interaction.

## Component-owned values

`useOwned` registers any Reactily object with a dot-call `delete()` method for component cleanup.

```lua
local function component(): Reactily.element
	local binding = Reactily.useOwned(
		Reactily.createBinding(0)
	)

	local diagnostics = Reactily.useOwned(
		Reactily.createDiagnostics()
	)

	return Reactily.createFrame({})
end
```

The objects are deleted when the component is permanently unmounted.

## Lifecycle-specific hooks

Use lifecycle hooks when the intent is clearer than a generic effect.

```lua
Reactily.useMount(function()
	print("Mounted")

	return function()
		print("Mount cleanup")
	end
end)

Reactily.useUpdateEffect(function()
	print("Updated")
end, {value})

Reactily.useUnmount(function()
	print("Unmounted")
end)
```

## Stable callbacks and latest values

`useEvent` returns a stable callback identity while always calling the latest callback implementation.

```lua
local onActivated = Reactily.useEvent(function()
	print(currentValue)
end)
```

`useLatest` returns a stable ref whose `current` field is refreshed on every render.

```lua
local latestValue = Reactily.useLatest(value)
```

These are useful for event handlers and long-lived subscriptions that should not be recreated just because captured values changed.

## External stores

`useExternalStore` adapts an external subscription contract into component state.

```lua
local value = Reactily.useExternalStore(
	function(onChanged)
		local connection = externalChanged:Connect(onChanged)

		return function()
			connection:Disconnect()
		end
	end,
	function()
		return readExternalValue()
	end
)
```

The subscription factory must return cleanup.

## Controlled or uncontrolled state

`useControllableState` supports components that can either receive a controlled value or own an internal fallback value.

```lua
local value, setValue = Reactily.useControllableState({
	value = props.value,
	defaultValue = 0,
	onChanged = props.onChanged,
})
```

## Focus, hover, and pressed state

Input-state hooks expose common GuiObject interaction state.

```lua
local isFocused = Reactily.useFocus(button)
local isHovered = Reactily.useHover(button)
local isPressed = Reactily.usePressed(button)
```

They are designed for component rendering, not for creating separate permanent polling loops.

## Stable IDs

`useId` creates a stable identifier for the component instance.

```lua
local id = Reactily.useId()
```

Use it for local identity, generated names, or related UI element relationships.

## Component-owned tweens

`useTween` owns a TweenService-backed Reactily animation for the component lifetime.

```lua
Reactily.useTween(
	frame,
	{
		Position = targetPosition,
	},
	{
		time = .2,
		easingStyle = Enum.EasingStyle.Quad,
		easingDirection = Enum.EasingDirection.Out,
	},
	{targetPosition}
)
```

When dependencies change, Reactily can replace the owned tween as part of the hook lifecycle.

## Fixed-size virtual lists

```lua
local list = Reactily.createVirtualList(
	1000,
	36,
	400,
	2
)
```

For direct stateless range calculations:

```lua
local range = Reactily.resolveVirtualList(
	1000,
	36,
	scrollOffset,
	400,
	2
)
```

Use `sliceVirtualList` to select only the values in a resolved range.

## Fixed-size virtual grids

```lua
local range = Reactily.resolveVirtualGrid(
	500,
	120,
	48,
	600,
	400,
	scrollOffsetY,
	8,
	8,
	2
)
```

The result identifies the item range needed for the visible rows plus overscan.

## Variable-size virtualization

```lua
local list = Reactily.createVariableVirtualList(
	{
		32,
		48,
		64,
		40,
	},
	300,
	2
)
```

For direct calculations:

```lua
local range = Reactily.resolveVariableVirtualList(
	itemSizes,
	scrollOffset,
	viewportSize,
	2
)
```

Use fixed-size virtualization when item sizes are uniform and variable-size virtualization when they are not.

## Profiling

Enable profiling explicitly:

```lua
Reactily.setProfilingEnabled(true)
```

Inspect one component:

```lua
local profile = Reactily.getProfile(component)
local reason = Reactily.getRenderReason(component)

print(profile, reason)
```

Inspect all profiles:

```lua
local snapshot = Reactily.getProfilerSnapshot()
local slowComponents = Reactily.getSlowComponents(10)

print(snapshot, slowComponents)
```

Clear recorded data:

```lua
Reactily.resetProfiler()
```

## Strict development checks

```lua
Reactily.setStrictMode(true)

print(
	Reactily.isStrictMode()
)
```

Strict mode is a development aid. It should not be used as a replacement for correct lifecycle ownership or typing.

## Root inspection

```lua
local snapshot = Reactily.inspectRoot(root)

print(snapshot)
```

Use root inspection with profiling and render reasons when diagnosing reconciliation or unnecessary render work.

---

# Using Systems Together

The examples below show complete workflows using multiple Reactily systems together.

## Store + selector + batch + memo

```lua
type appState = {
	page: string,
	count: number,
}

local store = Reactily.createStore<appState>({
	page = "Home",
	count = 0,
})

local countSelector = Reactily.createSelector(
	store,
	function(state: appState): number
		return state.count
	end
)

type props = {
	label: string,
}

local counter = Reactily.memo(function(props: props): Reactily.element
	local count = Reactily.useStore(
		store,
		function(state: appState): number
			return state.count
		end
	)

	return Reactily.createTextLabel({
		text = `{props.label}: {count}`,
	})
end)

Reactily.batch(function()
	store.update(function(previous: appState): appState
		return Reactily.patch(previous, {
			count = previous.count + 1,
		})
	end)

	store.update(function(previous: appState): appState
		return Reactily.patch(previous, {
			page = "Results",
		})
	end)
end)
```

## Context + memo + stable event

```lua
local context = Reactily.createContext({
	enabled = true,
})

local child = Reactily.memo(function(): Reactily.element
	local values = Reactily.useContext(context)

	local onActivated = Reactily.useEvent(function()
		print(values.enabled)
	end)

	return Reactily.createTextButton({
		text = tostring(values.enabled),
		onActivated = onActivated,
	})
end)

local tree = Reactily.createContextProvider(
	context,
	{
		enabled = true,
	},
	{
		Reactily.createComponent(child, {}),
	}
)
```

## Binding + spring + property synchronization

```lua
local target = Reactily.createBinding(0)
local spring = Reactily.createSpring(0, {
	frequency = 8,
	damping = 1,
})

local derived = Reactily.mapBinding(
	target,
	function(value: number): number
		return math.clamp(value, 0, 1)
	end
)

local cleanup = Reactily.bindAttribute(
	derived,
	instance,
	"Value",
	true
)

target.set(1)
spring.setTarget(target.get())

cleanup()
derived.delete()
target.delete()
spring.delete()
```

## Lazy + Suspense + error boundary

```lua
local lazyPanel = Reactily.lazy(function()
	return require(script.Parent.Panel)
end)

Reactily.preloadLazy(lazyPanel)

local loading = Reactily.createTextLabel({
	text = "Loading...",
})

local failed = Reactily.createTextLabel({
	text = "Unable to load.",
})

local content = Reactily.createComponent(
	lazyPanel,
	{}
)

local tree = Reactily.createErrorBoundary(
	failed,
	Reactily.createSuspense(
		loading,
		content
	),
	function(failure)
		warn(failure)
	end
)
```

## Transition + store + deferred component work

```lua
local function results(): Reactily.element
	local query = Reactily.useStore(
		searchStore,
		function(state)
			return state.query
		end
	)

	local deferredQuery = Reactily.useDeferredValue(query)
	local isPending, startTransition = Reactily.useTransition()

	local onSearch = Reactily.useEvent(function(nextQuery: string)
		startTransition(function()
			searchStore.update(function(previous)
				return Reactily.patch(previous, {
					query = nextQuery,
				})
			end)
		end)
	end)

	return Reactily.createTextLabel({
		text = if isPending
			then "Updating..."
			else deferredQuery,
	})
end
```

## Animation sequence + component lifetime

```lua
local function component(): Reactily.element
	local first = Reactily.useOwned(
		Reactily.createTween(
			firstFrame,
			{
				Position = UDim2.fromOffset(100, 0),
			},
			{
				time = .2,
			}
		)
	)

	local delay = Reactily.useOwned(
		Reactily.createAnimationDelay(.1)
	)

	local second = Reactily.useOwned(
		Reactily.createTween(
			secondFrame,
			{
				Position = UDim2.fromOffset(100, 0),
			},
			{
				time = .2,
			}
		)
	)

	local sequence = Reactily.useOwned(
		Reactily.sequenceAnimations({
			first,
			delay,
			second,
		})
	)

	Reactily.useMount(function()
		sequence.play()
	end)

	return Reactily.createFrame({})
end
```

## Profiling + strict mode + root inspection

```lua
Reactily.setStrictMode(true)
Reactily.setProfilingEnabled(true)

local root = Reactily.createRoot(playerGui)

root.render(
	Reactily.createComponent(app, {})
)

print(
	Reactily.inspectRoot(root)
)

for _, entry in Reactily.getSlowComponents(10) do
	print(entry)
end
```

## Virtualization + keyed elements

```lua
local range = Reactily.resolveVirtualList(
	#items,
	36,
	scrollOffset,
	viewportSize,
	2
)

local children = {}

for index = range.first, range.last do
	local item = items[index]

	children[#children + 1] = Reactily.key(
		tostring(item.id),
		Reactily.createTextLabel({
			text = item.name,
		})
	)
end
```

Stable keys let reconciliation preserve the correct child identity while virtualization changes the visible window.


---

# Complete 1.1 Public API Index

The production `src/init.luau` currently exposes **134 public functions**.

- `Reactily.applyStyle`
- `Reactily.batch`
- `Reactily.bindAttribute`
- `Reactily.bindProperty`
- `Reactily.clampBinding`
- `Reactily.clearFocus`
- `Reactily.combineBindings`
- `Reactily.combineBindingsMany`
- `Reactily.combineStores`
- `Reactily.createAnimationDelay`
- `Reactily.createAtom`
- `Reactily.createAttributeAtom`
- `Reactily.createBillboardGui`
- `Reactily.createBinding`
- `Reactily.createCanvasGroup`
- `Reactily.createComponent`
- `Reactily.createComputed`
- `Reactily.createContext`
- `Reactily.createDiagnostics`
- `Reactily.createElement`
- `Reactily.createErrorBoundary`
- `Reactily.createFocusGroup`
- `Reactily.createFragment`
- `Reactily.createFrame`
- `Reactily.createHistoryAtom`
- `Reactily.createImageButton`
- `Reactily.createImageLabel`
- `Reactily.createInstancePool`
- `Reactily.createLifecycleOwner`
- `Reactily.createObjectPool`
- `Reactily.createPortal`
- `Reactily.createResource`
- `Reactily.createRoot`
- `Reactily.createScheduler`
- `Reactily.createScreenGui`
- `Reactily.createScrollingFrame`
- `Reactily.createSelector`
- `Reactily.createSignal`
- `Reactily.createSpring`
- `Reactily.createStore`
- `Reactily.createStyle`
- `Reactily.createSurfaceGui`
- `Reactily.createSuspense`
- `Reactily.createTextBox`
- `Reactily.createTextButton`
- `Reactily.createTextLabel`
- `Reactily.createTheme`
- `Reactily.createTween`
- `Reactily.createUIAspectRatioConstraint`
- `Reactily.createUICorner`
- `Reactily.createUIGradient`
- `Reactily.createUIGridLayout`
- `Reactily.createUIListLayout`
- `Reactily.createUIPadding`
- `Reactily.createUIPageLayout`
- `Reactily.createUIScale`
- `Reactily.createUISizeConstraint`
- `Reactily.createUIStroke`
- `Reactily.createUITextSizeConstraint`
- `Reactily.createVariableVirtualList`
- `Reactily.createVideoFrame`
- `Reactily.createViewportFrame`
- `Reactily.createVirtualList`
- `Reactily.distinctSignal`
- `Reactily.filterSignal`
- `Reactily.flattenChildren`
- `Reactily.formatBinding`
- `Reactily.forwardRef`
- `Reactily.getProfile`
- `Reactily.getProfilerSnapshot`
- `Reactily.getSlowComponents`
- `Reactily.isStrictMode`
- `Reactily.lazy`
- `Reactily.mapBinding`
- `Reactily.mapSignal`
- `Reactily.memo`
- `Reactily.mergeSignals`
- `Reactily.new`
- `Reactily.parallelAnimations`
- `Reactily.patch`
- `Reactily.playTween`
- `Reactily.preloadLazy`
- `Reactily.resetProfiler`
- `Reactily.resolveTheme`
- `Reactily.resolveVariableVirtualList`
- `Reactily.resolveVirtualGrid`
- `Reactily.resolveVirtualList`
- `Reactily.roundBinding`
- `Reactily.sequenceAnimations`
- `Reactily.setProfilingEnabled`
- `Reactily.setStrictMode`
- `Reactily.shallowEqual`
- `Reactily.skipSignal`
- `Reactily.sliceVirtualList`
- `Reactily.takeSignal`
- `Reactily.useAttribute`
- `Reactily.useBinding`
- `Reactily.useBoolean`
- `Reactily.useCallback`
- `Reactily.useContext`
- `Reactily.useControllableState`
- `Reactily.useCounter`
- `Reactily.useDebouncedValue`
- `Reactily.useDeferredValue`
- `Reactily.useEffect`
- `Reactily.useEvent`
- `Reactily.useExternalStore`
- `Reactily.useFocus`
- `Reactily.useHover`
- `Reactily.useId`
- `Reactily.useImperativeHandle`
- `Reactily.useLatest`
- `Reactily.useLayoutEffect`
- `Reactily.useMemo`
- `Reactily.useMount`
- `Reactily.useOwned`
- `Reactily.usePressed`
- `Reactily.usePrevious`
- `Reactily.useReducer`
- `Reactily.useRef`
- `Reactily.useSpring`
- `Reactily.useState`
- `Reactily.useStore`
- `Reactily.useToggle`
- `Reactily.useTransition`
- `Reactily.useTween`
- `Reactily.useUnmount`
- `Reactily.useUpdateEffect`
- `Reactily.createContextProvider`
- `Reactily.getRenderReason`
- `Reactily.getVersion`
- `Reactily.inspectRoot`
- `Reactily.key`
- `Reactily.startTransition`

The remainder of this README documents the package by system, including returned-object APIs, typed creators, prop types, lifecycle behavior, and advanced module APIs.


# Public API Reference

All signatures below are exported from `src/init.luau`.

## Package

### `Reactily.getVersion`

```lua
Reactily.getVersion(): string
```

Returns `"1.1.0"`.

### `Reactily.new`

```lua
Reactily.new(parent: Instance): Reactily.root
```

Alias of `createRoot`.

### `Reactily.createRoot`

```lua
Reactily.createRoot(parent: Instance): Reactily.root
```

---

## Virtual Tree

### `Reactily.createElement`

```lua
Reactily.createElement(
	className: string,
	props: {[string]: any}?,
	children: {Reactily.element}?
): Reactily.element
```

### `Reactily.createComponent`

```lua
Reactily.createComponent<P>(
	componentValue: Reactily.component<P>,
	props: P,
	children: {Reactily.element}?,
	key: string?
): Reactily.element
```

### `Reactily.createFragment`

```lua
Reactily.createFragment(
	children: {Reactily.element},
	key: string?
): Reactily.element
```

### `Reactily.createPortal`

```lua
Reactily.createPortal(
	target: Instance,
	children: {Reactily.element},
	key: string?
): Reactily.element
```

---

## State Constructors

```lua
Reactily.createAtom<T>(initialValue: T): Reactily.atom<T>
```

```lua
Reactily.createComputed<A, B>(
	source: Reactily.atom<A>,
	selectorFunction: (value: A) -> B
): Reactily.computed<B>
```

```lua
Reactily.createHistoryAtom<T>(
	initialValue: T,
	limit: number
): Reactily.historyAtom<T>
```

```lua
Reactily.createAttributeAtom<T>(
	instance: Instance,
	attributeName: string,
	defaultValue: T
): Reactily.atom<T>
```

```lua
Reactily.createStore<T>(
	initialState: T
): Reactily.store<T>
```

---

## Binding API

```lua
Reactily.createBinding<T>(initialValue: T): Reactily.binding<T>
```

```lua
Reactily.mapBinding<A, B>(
	source: Reactily.binding<A>,
	mapper: (value: A) -> B
): Reactily.binding<B>
```

```lua
Reactily.combineBindings<A, B, R>(
	first: Reactily.binding<A>,
	second: Reactily.binding<B>,
	mapper: (firstValue: A, secondValue: B) -> R
): Reactily.binding<R>
```

```lua
Reactily.clampBinding(
	source: Reactily.binding<number>,
	minimum: number,
	maximum: number
): Reactily.binding<number>
```

```lua
Reactily.roundBinding(
	source: Reactily.binding<number>,
	precision: number
): Reactily.binding<number>
```

```lua
Reactily.formatBinding<T>(
	source: Reactily.binding<T>,
	formatter: (value: T) -> string
): Reactily.binding<string>
```

---

## Signal API

```lua
Reactily.createSignal<T>(): Reactily.signal<T>
```

```lua
Reactily.mapSignal<A, B>(
	source: Reactily.signal<A>,
	mapper: (value: A) -> B
): Reactily.signal<B>
```

```lua
Reactily.filterSignal<T>(
	source: Reactily.signal<T>,
	predicate: (value: T) -> boolean
): Reactily.signal<T>
```

```lua
Reactily.distinctSignal<T>(
	source: Reactily.signal<T>
): Reactily.signal<T>
```

```lua
Reactily.mergeSignals<T>(
	sources: {Reactily.signal<T>}
): Reactily.signal<T>
```

```lua
Reactily.skipSignal<T>(
	source: Reactily.signal<T>,
	amount: number
): Reactily.signal<T>
```

```lua
Reactily.takeSignal<T>(
	source: Reactily.signal<T>,
	maximum: number
): Reactily.signal<T>
```

---

## Hooks API

```lua
Reactily.useState<T>(
	initialValue: T
): (T, Reactily.stateSetter<T>)
```

```lua
Reactily.useReducer<S, A>(
	reducer: (stateValue: S, action: A) -> S,
	initialState: S
): (S, Reactily.reducerDispatch<A>)
```

```lua
Reactily.useRef<T>(
	initialValue: T
): Reactily.ref<T>
```

```lua
Reactily.useMemo<T>(
	factory: () -> T,
	dependencies: {any}?
): T
```

```lua
Reactily.useCallback<T>(
	callback: T,
	dependencies: {any}?
): T
```

```lua
Reactily.useEffect(
	callback: () -> (() -> ())?,
	dependencies: {any}?
)
```

```lua
Reactily.usePrevious<T>(
	value: T
): T?
```

```lua
Reactily.useToggle(
	initialValue: boolean?
): (
	boolean,
	() -> (),
	(value: boolean) -> ()
)
```

```lua
Reactily.useBoolean(
	initialValue: boolean?
): (
	boolean,
	() -> (),
	() -> (),
	() -> ()
)
```

```lua
Reactily.useCounter(
	initialValue: number?
): (
	number,
	Reactily.counterControls
)
```

```lua
Reactily.useDebouncedValue<T>(
	value: T,
	delaySeconds: number
): T
```

```lua
Reactily.useAttribute<T>(
	instance: Instance,
	attributeName: string,
	defaultValue: T
): (
	T,
	(value: T) -> ()
)
```

---

## Style and Theme API

```lua
Reactily.createStyle(styles: {Reactily.style}): Reactily.style
```

```lua
Reactily.applyStyle<T>(
	properties: T,
	styleValue: Reactily.style
): T
```

```lua
Reactily.createTheme<T>(
	initialValue: T
): Reactily.theme<T>
```

```lua
Reactily.resolveTheme<T, R>(
	themeValue: Reactily.theme<T>,
	selectorFunction: (tokens: T) -> R
): R
```

---

## Animation API

```lua
Reactily.createTween(
	instance: Instance,
	goals: {[string]: any},
	options: Reactily.tweenOptions
): Reactily.animation
```

```lua
Reactily.playTween(
	instance: Instance,
	goals: {[string]: any},
	options: Reactily.tweenOptions
): Reactily.animation
```

---

## Focus API

```lua
Reactily.createFocusGroup(): Reactily.focusGroup
```

```lua
Reactily.clearFocus()
```

---

## Virtual List API

```lua
Reactily.resolveVirtualList(
	itemCount: number,
	itemSize: number,
	scrollOffset: number,
	viewportSize: number,
	overscan: number?
): Reactily.virtualRange
```

```lua
Reactily.sliceVirtualList<T>(
	items: {T},
	rangeValue: Reactily.virtualRange
): {T}
```

---

## Pool API

```lua
Reactily.createObjectPool<T>(
	createObject: () -> T,
	resetObject: (object: T) -> (),
	deleteObject: (object: T) -> (),
	maximumSize: number
): Reactily.objectPool<T>
```

```lua
Reactily.createInstancePool(
	className: string,
	maximumSize: number
): Reactily.objectPool<Instance>
```

---

## Scheduler, Diagnostics, and Lifecycle

```lua
Reactily.createScheduler(): Reactily.scheduler
```

```lua
Reactily.createDiagnostics(): Reactily.diagnostics
```

```lua
Reactily.createLifecycleOwner(): Reactily.lifecycleOwner
```

---

---

# Reactily 1.1 Detailed API Additions

These APIs are part of the current `src/init.luau` public surface and were not present in the older 1.0 reference.

## `Reactily.batch`

Runs a callback inside a nested-safe global Reactily batch.

### Signature

```lua
Reactily.batch(callback: () -> ()): ()
```

### Usage

```lua
Reactily.batch(function()
	firstStore.set(firstValue)
	secondStore.set(secondValue)
end)
```

### Works with

Pairs naturally with `createStore`, store transactions, `patch`, selectors, atoms, bindings.

## `Reactily.bindAttribute`

Binds a reactive value to a Roblox Attribute with optional two-way synchronization.

### Signature

```lua
Reactily.bindAttribute<T>(source: binding<T>, instance: Instance, attributeName: string, twoWay: boolean?): () -> ()
```

### Usage

```lua
local cleanup = Reactily.bindAttribute(
	enabledBinding,
	instance,
	"Enabled",
	true
)

cleanup()
```

### Works with

Pairs naturally with `createBinding`, `mapBinding`, `combineBindings`, `combineBindingsMany`.

## `Reactily.bindProperty`

Binds a reactive value to a Roblox property with optional two-way synchronization.

### Signature

```lua
Reactily.bindProperty<T>(source: binding<T>, instance: Instance, propertyName: string, twoWay: boolean?): () -> ()
```

### Usage

```lua
local cleanup = Reactily.bindProperty(
	positionBinding,
	frame,
	"Position",
	true
)

cleanup()
```

### Works with

Pairs naturally with `createBinding`, `mapBinding`, `combineBindings`, `combineBindingsMany`.

## `Reactily.combineBindingsMany`

Combines any number of bindings using an ordered value array.

### Signature

```lua
Reactily.combineBindingsMany<R>(sources: {binding<any>}, mapper: (values: {any}) -> R): binding<R>
```

### Usage

```lua
local combined = Reactily.combineBindingsMany(
	{firstBinding, secondBinding},
	function(values)
		return {
			first = values[1],
			second = values[2],
		}
	end
)
```

### Works with

Pairs naturally with `createBinding`, `mapBinding`, `bindProperty`, `bindAttribute`.

## `Reactily.combineStores`

Combines multiple stores into one derived selector.

### Signature

```lua
Reactily.combineStores<R>(stores: {store<any>}, selectorFunction: (values: {any}) -> R): selector<R>
```

### Usage

```lua
local combined = Reactily.combineStores(
	{firstStore, secondStore},
	function(values)
		return values[1].value + values[2].value
	end
)
```

### Works with

Pairs naturally with `createStore`, `createSelector`, `useStore`, `batch`, `patch`.

## `Reactily.createAnimationDelay`

Creates a one-shot delay step compatible with Reactily animation sequences.

### Signature

```lua
Reactily.createAnimationDelay(seconds: number): animationPlayable
```

### Usage

```lua
local delay = Reactily.createAnimationDelay(.2)
```

### Works with

Pairs naturally with `createTween`, `parallelAnimations`, `sequenceAnimations`, `useOwned`.

## `Reactily.createContext`

Creates a typed Reactily context with a fallback value.

### Signature

```lua
Reactily.createContext<T>(defaultValue: T): context<T>
```

### Usage

```lua
local context = Reactily.createContext({
	enabled = true,
})
```

### Works with

Pairs naturally with `createContextProvider`, `useContext`, `memo`.

## `Reactily.createErrorBoundary`

Creates an error boundary around one child element.

### Signature

```lua
Reactily.createErrorBoundary(fallback: element | ((failure: any) -> element), child: element, onError: ((failure: any) -> ())?, key: string?): element
```

### Usage

```lua
local boundary = Reactily.createErrorBoundary(
	errorFallback,
	child,
	function(failure)
		warn(failure)
	end
)
```

### Works with

Pairs naturally with `createSuspense`, `lazy`, `createResource`.

## `Reactily.createResource`

Creates a lazy resource whose loader runs only when first requested.

### Signature

```lua
Reactily.createResource<T>(loader: () -> T): resource<T>
```

### Usage

```lua
local resource = Reactily.createResource(function()
	return loadData()
end)
```

### Works with

Pairs naturally with `createSuspense`, `createErrorBoundary`, lazy asynchronous UI.

## `Reactily.createSelector`

Creates a derived selector from one store.

### Signature

```lua
Reactily.createSelector<T, R>(source: store<T>, selectorFunction: (state: T) -> R): selector<R>
```

### Usage

```lua
local selector = Reactily.createSelector(
	store,
	function(state)
		return state.count
	end
)
```

### Works with

Pairs naturally with `createStore`, `combineStores`, `useStore`, `memo`.

## `Reactily.createSpring`

Creates a spring for number, Vector2, Vector3, or Color3 values.

### Signature

```lua
Reactily.createSpring<T>(initialValue: T, options: springOptions?): spring<T>
```

### Usage

```lua
local spring = Reactily.createSpring(0, {
	frequency = 8,
	damping = 1,
})

spring.setTarget(1)
```

### Works with

Pairs naturally with `useSpring`, bindings, component-owned lifecycle.

## `Reactily.createSuspense`

Creates a Suspense boundary around one child element.

### Signature

```lua
Reactily.createSuspense(fallback: element, child: element, key: string?): element
```

### Usage

```lua
local boundary = Reactily.createSuspense(
	loadingFallback,
	child
)
```

### Works with

Pairs naturally with `createResource`, `lazy`, `createErrorBoundary`.

## `Reactily.createVariableVirtualList`

Creates a cached controller for variable-size virtualized lists.

### Signature

```lua
Reactily.createVariableVirtualList(sizes: {number}, viewportSize: number, overscan: number?): variableVirtualList
```

### Usage

```lua
local list = Reactily.createVariableVirtualList(
	itemSizes,
	viewportSize,
	2
)
```

### Works with

Pairs naturally with `resolveVariableVirtualList`, keyed elements, scrolling containers.

## `Reactily.createVirtualList`

Creates a small stateful virtual-list virtualRange controller.

### Signature

```lua
Reactily.createVirtualList(itemCount: number, itemSize: number, viewportSize: number, overscan: number?): virtualList
```

### Usage

```lua
local list = Reactily.createVirtualList(
	1000,
	36,
	400,
	2
)
```

### Works with

Pairs naturally with `resolveVirtualList`, `sliceVirtualList`, keyed elements.

## `Reactily.flattenChildren`

Flattens nested Reactily child arrays and removes false/nil entries.

### Signature

```lua
Reactily.flattenChildren(children: {any}): {element}
```

### Usage

```lua
local children = Reactily.flattenChildren({
	first,
	{second, third},
	false,
	nil,
})
```

### Works with

Pairs naturally with `createFragment`, component children, keyed reconciliation.

## `Reactily.forwardRef`

Creates a component wrapper that forwards props.ref to the render callback.

### Signature

```lua
Reactily.forwardRef(render: (props: any, ref: refTarget<any>?) -> any): any
```

### Usage

```lua
local input = Reactily.forwardRef(function(props, ref)
	return Reactily.createTextBox({
		ref = ref,
		text = props.text,
	})
end)
```

### Works with

Pairs naturally with `useImperativeHandle`, `useRef`, typed host refs.

## `Reactily.getProfile`

Returns a copy of profile data for one component.

### Signature

```lua
Reactily.getProfile(componentValue: component<any>): componentProfile?
```

### Usage

```lua
local profile = Reactily.getProfile(component)
```

### Works with

Pairs naturally with `setProfilingEnabled`, `getRenderReason`, `inspectRoot`.

## `Reactily.getProfilerSnapshot`

Returns all currently collected component profiles.

### Signature

```lua
Reactily.getProfilerSnapshot(): {[any]: componentProfile}
```

### Usage

```lua
local profiles = Reactily.getProfilerSnapshot()
```

### Works with

Pairs naturally with `setProfilingEnabled`, `getSlowComponents`, `resetProfiler`.

## `Reactily.getSlowComponents`

Returns the slowest recorded components ordered by average render time.

### Signature

```lua
Reactily.getSlowComponents(limit: number?): {{component: any, profile: componentProfile}}
```

### Usage

```lua
local slowComponents = Reactily.getSlowComponents(10)
```

### Works with

Pairs naturally with `setProfilingEnabled`, `getProfilerSnapshot`, `getRenderReason`.

## `Reactily.isStrictMode`

Returns whether Reactily strict development checks are enabled.

### Signature

```lua
Reactily.isStrictMode(): boolean
```

### Usage

```lua
print(Reactily.isStrictMode())
```

### Works with

Pairs naturally with `setStrictMode`, diagnostics, development validation.

## `Reactily.lazy`

Creates a component whose implementation is loaded on first render.

### Signature

```lua
Reactily.lazy<T>(loader: () -> T): T
```

### Usage

```lua
local panel = Reactily.lazy(function()
	return require(script.Parent.Panel)
end)
```

### Works with

Pairs naturally with `preloadLazy`, `createSuspense`, `createErrorBoundary`.

## `Reactily.memo`

Wraps a component with a memoization comparator.

### Signature

```lua
Reactily.memo<T>(componentValue: T, comparator: ((previousProps: {[string]: any}, nextProps: {[string]: any}) -> boolean)?): T
```

### Usage

```lua
local optimizedComponent = Reactily.memo(component)
```

### Works with

Pairs naturally with `shallowEqual`, selectors, immutable `patch`, context.

## `Reactily.parallelAnimations`

Creates a group that starts every animation together.

### Signature

```lua
Reactily.parallelAnimations(animations: {animationPlayable}): animationGroup
```

### Usage

```lua
local group = Reactily.parallelAnimations({
	firstAnimation,
	secondAnimation,
})

group.play()
```

### Works with

Pairs naturally with `createTween`, `createAnimationDelay`, `sequenceAnimations`.

## `Reactily.patch`

Returns a shallow clone with the supplied fields replaced.

### Signature

```lua
Reactily.patch<T>(source: T, changes: {[any]: any}): T
```

### Usage

```lua
local nextState = Reactily.patch(previousState, {
	page = "Settings",
})
```

### Works with

Pairs naturally with `createStore`, `batch`, selectors, memoized components.

## `Reactily.preloadLazy`

Starts loading a lazy component before it is rendered.

### Signature

```lua
Reactily.preloadLazy(componentValue: component<any>): boolean
```

### Usage

```lua
Reactily.preloadLazy(lazyComponent)
```

### Works with

Pairs naturally with `lazy`, `createSuspense`, route/page preparation.

## `Reactily.resetProfiler`

Clears all collected profiler data.

### Signature

```lua
Reactily.resetProfiler(): ()
```

### Usage

```lua
Reactily.resetProfiler()
```

### Works with

Pairs naturally with `setProfilingEnabled`, `getProfilerSnapshot`, `getSlowComponents`.

## `Reactily.resolveVariableVirtualList`

Resolves a visible range for variable-size items.

### Signature

```lua
Reactily.resolveVariableVirtualList(sizes: {number}, scrollOffset: number, viewportSize: number, overscan: number?): variableVirtualRange
```

### Usage

```lua
local range = Reactily.resolveVariableVirtualList(
	itemSizes,
	scrollOffset,
	viewportSize,
	2
)
```

### Works with

Pairs naturally with `createVariableVirtualList`, scrolling containers, keyed elements.

## `Reactily.resolveVirtualGrid`

Resolves the visible item range for a fixed-size grid.

### Signature

```lua
Reactily.resolveVirtualGrid(itemCount: number, cellWidth: number, cellHeight: number, viewportWidth: number, viewportHeight: number, scrollOffsetY: number, horizontalGap: number?, verticalGap: number?, overscanRows: number?): gridRange
```

### Usage

```lua
local range = Reactily.resolveVirtualGrid(
	500,
	120,
	48,
	600,
	400,
	scrollOffsetY,
	8,
	8,
	2
)
```

### Works with

Pairs naturally with grid UI, keyed children, fixed-cell virtualization.

## `Reactily.sequenceAnimations`

Creates a group that plays each animation after the previous one completes.

### Signature

```lua
Reactily.sequenceAnimations(animations: {animationPlayable}): animationGroup
```

### Usage

```lua
local group = Reactily.sequenceAnimations({
	firstAnimation,
	Reactily.createAnimationDelay(.1),
	secondAnimation,
})

group.play()
```

### Works with

Pairs naturally with `createTween`, `createAnimationDelay`, `parallelAnimations`.

## `Reactily.setProfilingEnabled`

Enables or disables component profiling.

### Signature

```lua
Reactily.setProfilingEnabled(value: boolean): ()
```

### Usage

```lua
Reactily.setProfilingEnabled(true)
```

### Works with

Pairs naturally with `getProfile`, `getProfilerSnapshot`, `getSlowComponents`, `getRenderReason`.

## `Reactily.setStrictMode`

Enables or disables additional development-time Reactily warnings.

### Signature

```lua
Reactily.setStrictMode(enabled: boolean): ()
```

### Usage

```lua
Reactily.setStrictMode(true)
```

### Works with

Pairs naturally with `isStrictMode`, diagnostics, development checks.

## `Reactily.shallowEqual`

Performs a shallow key/value equality comparison between two tables.

### Signature

```lua
Reactily.shallowEqual(first: {[any]: any}?, second: {[any]: any}?): boolean
```

### Usage

```lua
local equal = Reactily.shallowEqual(
	previousProps,
	nextProps
)
```

### Works with

Pairs naturally with `memo`, immutable `patch`, selector comparisons.

## `Reactily.useBinding`

Creates and owns a Reactily binding for the component lifetime.

### Signature

```lua
Reactily.useBinding<T>(initialValue: T): binding<T>
```

### Usage

```lua
local binding = Reactily.useBinding(0)
```

### Works with

Pairs naturally with `bindProperty`, `bindAttribute`, binding transforms.

## `Reactily.useContext`

Reads the current value from a Reactily context.

### Signature

```lua
Reactily.useContext<T>(contextValue: context<T>): T
```

### Usage

```lua
local value = Reactily.useContext(context)
```

### Works with

Pairs naturally with `createContext`, `createContextProvider`, `memo`.

## `Reactily.useControllableState`

Creates state that can be controlled by props or managed internally.

### Signature

```lua
Reactily.useControllableState<T>(options: controllableStateOptions<T>): (T, stateSetter<T>)
```

### Usage

```lua
local value, setValue = Reactily.useControllableState({
	value = props.value,
	defaultValue = 0,
	onChanged = props.onChanged,
})
```

### Works with

Pairs naturally with controlled component props, `useEvent`, typed creators.

## `Reactily.useDeferredValue`

Returns a deferred copy of a changing value using one-shot scheduling.

### Signature

```lua
Reactily.useDeferredValue<T>(value: T): T
```

### Usage

```lua
local deferredValue = Reactily.useDeferredValue(value)
```

### Works with

Pairs naturally with `useTransition`, stores, search/filter UIs.

## `Reactily.useEvent`

Creates a stable callback that always invokes the latest callback body.

### Signature

```lua
Reactily.useEvent<T>(callback: T): T
```

### Usage

```lua
local onActivated = Reactily.useEvent(function()
	print(value)
end)
```

### Works with

Pairs naturally with `useLatest`, event props, external subscriptions.

## `Reactily.useExternalStore`

Subscribes a component to any external store contract.

### Signature

```lua
Reactily.useExternalStore<T>(subscribe: (callback: () -> ()) -> (() -> ()), getSnapshot: () -> T): T
```

### Usage

```lua
local value = Reactily.useExternalStore(
	subscribe,
	getSnapshot
)
```

### Works with

Pairs naturally with external signals/stores, lifecycle cleanup, `useEvent`.

## `Reactily.useFocus`

Returns focus state for a GuiObject.

### Signature

```lua
Reactily.useFocus(object: GuiObject): boolean
```

### Usage

```lua
local isFocused = Reactily.useFocus(button)
```

### Works with

Pairs naturally with `createFocusGroup`, typed buttons, focus navigation.

## `Reactily.useHover`

Returns hover state for a GuiObject.

### Signature

```lua
Reactily.useHover(object: GuiObject): boolean
```

### Usage

```lua
local isHovered = Reactily.useHover(button)
```

### Works with

Pairs naturally with `usePressed`, styles, interactive GuiObjects.

## `Reactily.useId`

Returns a stable component-local identifier.

### Signature

```lua
Reactily.useId(): string
```

### Usage

```lua
local id = Reactily.useId()
```

### Works with

Pairs naturally with component identity, generated names, refs.

## `Reactily.useImperativeHandle`

Creates or updates an imperative handle exposed through a Reactily ref.

### Signature

```lua
Reactily.useImperativeHandle<T>(target: refTarget<T>?, factory: () -> T, dependencies: {any}?): ()
```

### Usage

```lua
Reactily.useImperativeHandle(
	ref,
	function()
		return {
			focus = function()
				textBox:CaptureFocus()
			end,
		}
	end,
	{}
)
```

### Works with

Pairs naturally with `forwardRef`, `useRef`, typed refs.

## `Reactily.useLatest`

Returns a stable ref whose current field is refreshed every render.

### Signature

```lua
Reactily.useLatest<T>(value: T): ref<T>
```

### Usage

```lua
local latestValue = Reactily.useLatest(value)
```

### Works with

Pairs naturally with `useEvent`, effects, long-lived subscriptions.

## `Reactily.useLayoutEffect`

Queues an effect for the layout phase before normal effects.

### Signature

```lua
Reactily.useLayoutEffect(callback: () -> (() -> ())?, dependencies: {any}?): ()
```

### Usage

```lua
Reactily.useLayoutEffect(function()
	updateLayout()
end, {size})
```

### Works with

Pairs naturally with `useTween`, refs, layout-sensitive work.

## `Reactily.useMount`

Runs an effect once when the component mounts.

### Signature

```lua
Reactily.useMount(callback: () -> (() -> ())?): ()
```

### Usage

```lua
Reactily.useMount(function()
	print("Mounted")
end)
```

### Works with

Pairs naturally with `useUnmount`, `useOwned`, subscriptions.

## `Reactily.useOwned`

Registers a delete-capable object for automatic component cleanup.

### Signature

```lua
Reactily.useOwned<T>(value: T): T
```

### Usage

```lua
local binding = Reactily.useOwned(
	Reactily.createBinding(0)
)
```

### Works with

Pairs naturally with bindings, springs, animations, diagnostics, lifecycle owners.

## `Reactily.usePressed`

Returns pressed state for a GuiButton or GuiObject input surface.

### Signature

```lua
Reactily.usePressed(object: GuiObject): boolean
```

### Usage

```lua
local isPressed = Reactily.usePressed(button)
```

### Works with

Pairs naturally with `useHover`, `useFocus`, interactive styles.

## `Reactily.useSpring`

Creates a component-owned spring and updates its target when the input changes.

### Signature

```lua
Reactily.useSpring<T>(target: T, options: springOptions?): spring<T>
```

### Usage

```lua
local spring = Reactily.useSpring(target, {
	frequency = 8,
	damping = 1,
})
```

### Works with

Pairs naturally with `createSpring`, component state, animation.

## `Reactily.useStore`

Subscribes a component to a Reactily store, optionally selecting one derived value.

### Signature

```lua
Reactily.useStore<S>(storeValue: store<S>, selectorFunction: ((state: S) -> any)?): any
```

### Usage

```lua
local count = Reactily.useStore(
	store,
	function(state)
		return state.count
	end
)
```

### Works with

Pairs naturally with `createStore`, `createSelector`, `combineStores`, `batch`.

## `Reactily.useTransition`

Creates a low-priority transition starter and pending state.

### Signature

```lua
Reactily.useTransition(): (boolean, transitionStarter)
```

### Usage

```lua
local isPending, startTransition = Reactily.useTransition()

startTransition(function()
	updateState()
end)
```

### Works with

Pairs naturally with `startTransition`, `useDeferredValue`, stores.

## `Reactily.useTween`

Creates and owns a TweenService animation while dependencies remain current.

### Signature

```lua
Reactily.useTween(instance: Instance, goals: {[string]: any}, options: tweenOptions, dependencies: {any}?): animation?
```

### Usage

```lua
Reactily.useTween(
	frame,
	{
		Position = targetPosition,
	},
	{
		time = .2,
	},
	{targetPosition}
)
```

### Works with

Pairs naturally with `createTween`, `useLayoutEffect`, component ownership.

## `Reactily.useUnmount`

Registers cleanup that runs only when the component unmounts.

### Signature

```lua
Reactily.useUnmount(callback: () -> ()): ()
```

### Usage

```lua
Reactily.useUnmount(function()
	print("Unmounted")
end)
```

### Works with

Pairs naturally with `useMount`, `useOwned`, effect cleanup.

## `Reactily.useUpdateEffect`

Runs an effect only after the initial completed render.

### Signature

```lua
Reactily.useUpdateEffect(callback: () -> (() -> ())?, dependencies: {any}?): ()
```

### Usage

```lua
Reactily.useUpdateEffect(function()
	print("Updated")
end, {value})
```

### Works with

Pairs naturally with `useEffect`, `useMount`, dependency-based work.

## `Reactily.createContextProvider`

Creates a provider element for a Reactily context.

### Signature

```lua
Reactily.createContextProvider<T>(contextValue: context<T>, value: T, children: {any}, key: string?): element
```

### Usage

```lua
local provider = Reactily.createContextProvider(
	context,
	value,
	{
		child,
	}
)
```

### Works with

Pairs naturally with `createContext`, `useContext`, component trees.

## `Reactily.getRenderReason`

Returns the latest recorded reason a component rendered.

### Signature

```lua
Reactily.getRenderReason(componentValue: any): string?
```

### Usage

```lua
local reason = Reactily.getRenderReason(component)
```

### Works with

Pairs naturally with `setProfilingEnabled`, `getProfile`, `inspectRoot`.

## `Reactily.inspectRoot`

Returns a diagnostic snapshot of a mounted Reactily root tree.

### Signature

```lua
Reactily.inspectRoot(rootValue: root): any
```

### Usage

```lua
local snapshot = Reactily.inspectRoot(root)
```

### Works with

Pairs naturally with profiling, render reasons, reconciliation diagnostics.

## `Reactily.key`

Returns a clone of an element with a stable key.

### Signature

```lua
Reactily.key(key: string, elementValue: element): element
```

### Usage

```lua
local keyed = Reactily.key(
	tostring(item.id),
	element
)
```

### Works with

Pairs naturally with lists, virtualization, keyed reconciliation.

## `Reactily.startTransition`

Starts low-priority one-shot transition work.

### Signature

```lua
Reactily.startTransition(callback: () -> ()): thread
```

### Usage

```lua
Reactily.startTransition(function()
	updateState()
end)
```

### Works with

Pairs naturally with `useTransition`, `useDeferredValue`, low-priority store updates.

# Returned Object APIs

## `root`

```lua
type root = {
	batch: (callback: () -> ()) -> (),
	delete: () -> boolean,
	flush: () -> (),
	getElement: () -> Reactily.element?,
	getParent: () -> Instance,
	isDeleted: () -> boolean,
	isSuspended: () -> boolean,
	render: (elementValue: Reactily.element?) -> (),
	resume: () -> boolean,
	suspend: () -> boolean,
}
```

## `atom<T>`

```lua
type atom<T> = {
	delete: () -> boolean,
	get: () -> T,
	isDeleted: () -> boolean,
	set: (value: T) -> boolean,
	subscribe: (callback: (change: Reactily.atomChange<T>) -> ()) -> Reactily.connection,
	update: (updater: (previous: T) -> T) -> boolean,
}
```

## `computed<T>`

```lua
type computed<T> = {
	delete: () -> boolean,
	get: () -> T,
	isDeleted: () -> boolean,
	subscribe: (callback: (change: Reactily.atomChange<T>) -> ()) -> Reactily.connection,
}
```

## `historyAtom<T>`

```lua
type historyAtom<T> = Reactily.atom<T> & {
	canRedo: () -> boolean,
	canUndo: () -> boolean,
	clearHistory: () -> (),
	getFutureCount: () -> number,
	getPastCount: () -> number,
	redo: () -> boolean,
	undo: () -> boolean,
}
```

## `store<T>`

```lua
type store<T> = {
	batch: (callback: () -> ()) -> (),
	delete: () -> boolean,
	get: () -> T,
	isDeleted: () -> boolean,
	reset: () -> boolean,
	select: <R>((state: T) -> R) -> Reactily.selector<R>,
	set: (state: T) -> boolean,
	subscribe: (callback: (change: {
		current: T,
		previous: T,
	}) -> ()) -> Reactily.connection,
	update: (updater: (state: T) -> T) -> boolean,
}
```

## `selector<T>`

```lua
type selector<T> = {
	delete: () -> boolean,
	get: () -> T,
	isDeleted: () -> boolean,
	subscribe: (callback: (change: {
		current: T,
		previous: T,
	}) -> ()) -> Reactily.connection,
}
```

## `binding<T>`

```lua
type binding<T> = {
	delete: () -> boolean,
	get: () -> T,
	isDeleted: () -> boolean,
	set: (value: T) -> boolean,
	subscribe: (callback: (change: Reactily.bindingChange<T>) -> ()) -> Reactily.connection,
}
```

## `signal<T>`

```lua
type signal<T> = {
	connect: (callback: (value: T) -> ()) -> Reactily.connection,
	delete: () -> boolean,
	fire: (value: T) -> (),
	getListenerCount: () -> number,
	isDeleted: () -> boolean,
	once: (callback: (value: T) -> ()) -> Reactily.connection,
}
```

## `connection`

```lua
type connection = {
	connected: boolean,
	disconnect: () -> boolean,
}
```

## `scheduler`

```lua
type scheduler = {
	cancel: (taskId: number) -> boolean,
	cancelKey: (key: string) -> boolean,
	clear: () -> (),
	delete: () -> boolean,
	enqueue: (callback: () -> ()) -> number,
	enqueueKeyed: (key: string, callback: () -> ()) -> number,
	flush: () -> (),
	getPendingCount: () -> number,
	isDeleted: () -> boolean,
	isPending: (key: string) -> boolean,
}
```

## `objectPool<T>`

```lua
type objectPool<T> = {
	acquire: () -> T,
	clear: () -> (),
	delete: () -> boolean,
	getAvailableCount: () -> number,
	getCreatedCount: () -> number,
	isDeleted: () -> boolean,
	release: (object: T) -> boolean,
}
```

## `animation`

```lua
type animation = {
	cancel: () -> boolean,
	delete: () -> boolean,
	isDeleted: () -> boolean,
	onCompleted: (callback: (playbackState: Enum.PlaybackState) -> ()) -> RBXScriptConnection,
	play: () -> (),
	tween: Tween,
}
```

## `tweenOptions`

```lua
type tweenOptions = {
	delayTime: number?,
	easingDirection: Enum.EasingDirection?,
	easingStyle: Enum.EasingStyle?,
	repeatCount: number?,
	reverses: boolean?,
	time: number,
}
```

| Option | Default |
| --- | --- |
| `delayTime` | `0` |
| `easingDirection` | `Enum.EasingDirection.Out` |
| `easingStyle` | `Enum.EasingStyle.Quad` |
| `repeatCount` | `0` |
| `reverses` | `false` |
| `time` | Required |

## `theme<T>`

```lua
type theme<T> = {
	delete: () -> boolean,
	get: () -> T,
	isDeleted: () -> boolean,
	set: (value: T) -> boolean,
	subscribe: (callback: (value: T) -> ()) -> Reactily.connection,
	update: (updater: (value: T) -> T) -> boolean,
}
```

## `focusGroup`

```lua
type focusGroup = {
	add: (object: GuiObject) -> boolean,
	clear: () -> (),
	delete: () -> boolean,
	focusFirst: () -> boolean,
	focusLast: () -> boolean,
	getItems: () -> {GuiObject},
	isDeleted: () -> boolean,
	remove: (object: GuiObject) -> boolean,
}
```

## `diagnostics`

```lua
type diagnostics = {
	delete: () -> boolean,
	get: (name: string) -> number,
	increment: (name: string, amount: number?) -> number,
	isDeleted: () -> boolean,
	reset: (name: string) -> boolean,
	resetAll: () -> (),
	snapshot: () -> {[string]: number},
}
```

## `counterControls`

```lua
type counterControls = {
	decrement: (amount: number?) -> (),
	increment: (amount: number?) -> (),
	reset: () -> (),
	set: (value: number) -> (),
}
```

## `ref<T>`

```lua
type ref<T> = {
	current: T,
}
```

## `virtualRange`

```lua
type virtualRange = {
	first: number,
	last: number,
	offset: number,
	totalSize: number,
}
```

---


## Reactily 1.1 returned types

The 1.1 root also exports these public types:

```lua
Reactily.animationGroup
Reactily.animationPlayable
Reactily.componentProfile
Reactily.context<T>
Reactily.controllableStateOptions<T>
Reactily.gridRange
Reactily.refTarget<T>
Reactily.resource<T>
Reactily.resourceStatus
Reactily.spring<T>
Reactily.springOptions
Reactily.storeMiddleware<T>
Reactily.transitionStarter
Reactily.variableVirtualList
Reactily.variableVirtualRange
Reactily.virtualList
```

Use these exported types for annotations rather than reaching into implementation modules.

Typical examples:

```lua
local context: Reactily.context<boolean> =
	Reactily.createContext(false)

local spring: Reactily.spring<number> =
	Reactily.createSpring(0)

local resource: Reactily.resource<any> =
	Reactily.createResource(function()
		return loadData()
	end)

local list: Reactily.variableVirtualList =
	Reactily.createVariableVirtualList(
		itemSizes,
		viewportSize,
		2
	)
```


# Typed Creator Reference

All class-specific creators return `Reactily.element`.

| Creator | Props | Children | Roblox host |
| --- | --- | --- | --- |
| `createBillboardGui` | `billboardGuiProps?` | Yes | `BillboardGui` |
| `createCanvasGroup` | `canvasGroupProps?` | Yes | `CanvasGroup` |
| `createFrame` | `frameProps?` | Yes | `Frame` |
| `createImageButton` | `imageButtonProps?` | Yes | `ImageButton` |
| `createImageLabel` | `imageLabelProps?` | Yes | `ImageLabel` |
| `createScreenGui` | `screenGuiProps?` | Yes | `ScreenGui` |
| `createScrollingFrame` | `scrollingFrameProps?` | Yes | `ScrollingFrame` |
| `createSurfaceGui` | `surfaceGuiProps?` | Yes | `SurfaceGui` |
| `createTextBox` | `textBoxProps?` | Yes | `TextBox` |
| `createTextButton` | `textButtonProps?` | Yes | `TextButton` |
| `createTextLabel` | `textLabelProps?` | Yes | `TextLabel` |
| `createUIAspectRatioConstraint` | `uiAspectRatioConstraintProps?` | No | `UIAspectRatioConstraint` |
| `createUICorner` | `uiCornerProps?` | No | `UICorner` |
| `createUIGradient` | `uiGradientProps?` | No | `UIGradient` |
| `createUIGridLayout` | `uiGridLayoutProps?` | No | `UIGridLayout` |
| `createUIListLayout` | `uiListLayoutProps?` | No | `UIListLayout` |
| `createUIPadding` | `uiPaddingProps?` | No | `UIPadding` |
| `createUIPageLayout` | `uiPageLayoutProps?` | No | `UIPageLayout` |
| `createUIScale` | `uiScaleProps?` | No | `UIScale` |
| `createUISizeConstraint` | `uiSizeConstraintProps?` | No | `UISizeConstraint` |
| `createUIStroke` | `uiStrokeProps?` | No | `UIStroke` |
| `createUITextSizeConstraint` | `uiTextSizeConstraintProps?` | No | `UITextSizeConstraint` |
| `createVideoFrame` | `videoFrameProps?` | Yes | `VideoFrame` |
| `createViewportFrame` | `viewportFrameProps?` | Yes | `ViewportFrame` |

Virtual-tree helpers:

| Function | Purpose |
| --- | --- |
| `createComponent` | Function component |
| `createElement` | Generic Roblox host |
| `createFragment` | Group children without a host |
| `createPortal` | Render children into another target |

---

# Typed Prop Reference

Reactily host prop names use camelCase and are mapped to the corresponding Roblox property/event names by the host configuration.

The sections below reproduce the public prop contracts from `src/virtual/element.luau`.

### `attributeValue`

```lua
export type attributeValue =
	boolean
	| BrickColor
	| CFrame
	| Color3
	| ColorSequence
	| NumberRange
	| NumberSequence
	| number
	| Rect
	| string
	| UDim
	| UDim2
	| Vector2
	| Vector3
```

### `hostMetadataProps`

```lua
export type hostMetadataProps<T> = {
	attributes: attributeMap?,
	key: string?,
	name: string?,
	ref: refCallback<T>?,
	tags: {string}?,
	onAncestryChanged: ((child: Instance, parent: Instance?) -> ())?,
	onChanged: ((property: string) -> ())?,
}
```

### `commonGuiProps`

```lua
export type commonGuiProps<T> = hostMetadataProps<T> & {
	active: boolean?,
	anchorPoint: Vector2?,
	automaticSize: Enum.AutomaticSize?,
	backgroundColor3: Color3?,
	backgroundTransparency: number?,
	borderColor3: Color3?,
	borderMode: Enum.BorderMode?,
	borderSizePixel: number?,
	clipsDescendants: boolean?,
	layoutOrder: number?,
	nextSelectionDown: GuiObject?,
	nextSelectionLeft: GuiObject?,
	nextSelectionRight: GuiObject?,
	nextSelectionUp: GuiObject?,
	position: UDim2?,
	rotation: number?,
	selectable: boolean?,
	selectionOrder: number?,
	size: UDim2?,
	sizeConstraint: Enum.SizeConstraint?,
	visible: boolean?,
	zIndex: number?,
	onInputBegan: ((input: InputObject) -> ())?,
	onInputChanged: ((input: InputObject) -> ())?,
	onInputEnded: ((input: InputObject) -> ())?,
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
	onSelectionGained: (() -> ())?,
	onSelectionLost: (() -> ())?,
}
```

### `textProps`

```lua
export type textProps = {
	font: Enum.Font?,
	fontFace: Font?,
	lineHeight: number?,
	maxVisibleGraphemes: number?,
	richText: boolean?,
	text: string?,
	textColor3: Color3?,
	textDirection: Enum.TextDirection?,
	textScaled: boolean?,
	textSize: number?,
	textStrokeColor3: Color3?,
	textStrokeTransparency: number?,
	textTransparency: number?,
	textTruncate: Enum.TextTruncate?,
	textWrapped: boolean?,
	textXAlignment: Enum.TextXAlignment?,
	textYAlignment: Enum.TextYAlignment?,
}
```

### `imageProps`

```lua
export type imageProps = {
	image: string?,
	imageColor3: Color3?,
	imageRectOffset: Vector2?,
	imageRectSize: Vector2?,
	imageTransparency: number?,
	resampleMode: Enum.ResamplerMode?,
	scaleType: Enum.ScaleType?,
	sliceCenter: Rect?,
	sliceScale: number?,
	tileSize: UDim2?,
}
```

### `buttonEvents`

```lua
export type buttonEvents = {
	onActivated: ((input: InputObject, clickCount: number) -> ())?,
	onMouseButton1Click: (() -> ())?,
	onMouseButton1Down: ((x: number, y: number) -> ())?,
	onMouseButton1Up: ((x: number, y: number) -> ())?,
	onMouseButton2Click: (() -> ())?,
	onMouseButton2Down: ((x: number, y: number) -> ())?,
	onMouseButton2Up: ((x: number, y: number) -> ())?,
}
```

### `billboardGuiProps`

```lua
export type billboardGuiProps = hostMetadataProps<BillboardGui> & {
	active: boolean?,
	adornee: Instance?,
	alwaysOnTop: boolean?,
	brightness: number?,
	clipsDescendants: boolean?,
	enabled: boolean?,
	extentsOffset: Vector3?,
	extentsOffsetWorldSpace: Vector3?,
	lightInfluence: number?,
	maxDistance: number?,
	playerToHideFrom: Player?,
	size: UDim2?,
	sizeOffset: Vector2?,
	studsOffset: Vector3?,
	studsOffsetWorldSpace: Vector3?,
	zIndexBehavior: Enum.ZIndexBehavior?,
}
```

### `canvasGroupProps`

```lua
export type canvasGroupProps = commonGuiProps<CanvasGroup> & {
	groupColor3: Color3?,
	groupTransparency: number?,
}
```

### `frameProps`

```lua
export type frameProps = commonGuiProps<Frame> & {
	style: Enum.FrameStyle?,
}
```

### `imageButtonProps`

```lua
export type imageButtonProps = commonGuiProps<ImageButton> & imageProps & buttonEvents & {
	autoButtonColor: boolean?,
	hoverImage: string?,
	modal: boolean?,
	pressedImage: string?,
	selected: boolean?,
}
```

### `imageLabelProps`

```lua
export type imageLabelProps = commonGuiProps<ImageLabel> & imageProps
```

### `screenGuiProps`

```lua
export type screenGuiProps = hostMetadataProps<ScreenGui> & {
	clipToDeviceSafeArea: boolean?,
	displayOrder: number?,
	enabled: boolean?,
	ignoreGuiInset: boolean?,
	resetOnSpawn: boolean?,
	safeAreaCompatibility: Enum.SafeAreaCompatibility?,
	screenInsets: Enum.ScreenInsets?,
	zIndexBehavior: Enum.ZIndexBehavior?,
}
```

### `scrollingFrameProps`

```lua
export type scrollingFrameProps = commonGuiProps<ScrollingFrame> & {
	automaticCanvasSize: Enum.AutomaticSize?,
	bottomImage: string?,
	canvasPosition: Vector2?,
	canvasSize: UDim2?,
	elasticBehavior: Enum.ElasticBehavior?,
	midImage: string?,
	scrollBarImageColor3: Color3?,
	scrollBarImageTransparency: number?,
	scrollBarThickness: number?,
	scrollingDirection: Enum.ScrollingDirection?,
	scrollingEnabled: boolean?,
	topImage: string?,
	verticalScrollBarInset: Enum.ScrollBarInset?,
	verticalScrollBarPosition: Enum.VerticalScrollBarPosition?,
}
```

### `surfaceGuiProps`

```lua
export type surfaceGuiProps = hostMetadataProps<SurfaceGui> & {
	active: boolean?,
	adornee: BasePart?,
	alwaysOnTop: boolean?,
	brightness: number?,
	canvasSize: Vector2?,
	clipsDescendants: boolean?,
	enabled: boolean?,
	face: Enum.NormalId?,
	lightInfluence: number?,
	maxDistance: number?,
	pixelsPerStud: number?,
	sizingMode: Enum.SurfaceGuiSizingMode?,
	toolPunchThroughDistance: number?,
	zIndexBehavior: Enum.ZIndexBehavior?,
	zOffset: number?,
}
```

### `textBoxProps`

```lua
export type textBoxProps = commonGuiProps<TextBox> & textProps & {
	clearTextOnFocus: boolean?,
	cursorPosition: number?,
	multiLine: boolean?,
	placeholderColor3: Color3?,
	placeholderText: string?,
	selectionStart: number?,
	showNativeInput: boolean?,
	textEditable: boolean?,
	onFocused: (() -> ())?,
	onFocusLost: ((enterPressed: boolean, input: InputObject?) -> ())?,
}
```

### `textButtonProps`

```lua
export type textButtonProps = commonGuiProps<TextButton> & textProps & buttonEvents & {
	autoButtonColor: boolean?,
	modal: boolean?,
	selected: boolean?,
	style: Enum.ButtonStyle?,
}
```

### `textLabelProps`

```lua
export type textLabelProps = commonGuiProps<TextLabel> & textProps
```

### `videoFrameProps`

```lua
export type videoFrameProps = commonGuiProps<VideoFrame> & {
	looped: boolean?,
	playing: boolean?,
	timePosition: number?,
	video: string?,
	volume: number?,
}
```

### `viewportFrameProps`

```lua
export type viewportFrameProps = commonGuiProps<ViewportFrame> & {
	ambient: Color3?,
	currentCamera: Camera?,
	imageColor3: Color3?,
	imageTransparency: number?,
	lightColor: Color3?,
	lightDirection: Vector3?,
}
```

### `uiAspectRatioConstraintProps`

```lua
export type uiAspectRatioConstraintProps = hostMetadataProps<UIAspectRatioConstraint> & {
	aspectRatio: number?,
	aspectType: Enum.AspectType?,
	dominantAxis: Enum.DominantAxis?,
}
```

### `uiCornerProps`

```lua
export type uiCornerProps = hostMetadataProps<UICorner> & {
	cornerRadius: UDim?,
}
```

### `uiGradientProps`

```lua
export type uiGradientProps = hostMetadataProps<UIGradient> & {
	color: ColorSequence?,
	enabled: boolean?,
	offset: Vector2?,
	rotation: number?,
	transparency: NumberSequence?,
}
```

### `uiGridLayoutProps`

```lua
export type uiGridLayoutProps = hostMetadataProps<UIGridLayout> & {
	cellPadding: UDim2?,
	cellSize: UDim2?,
	fillDirection: Enum.FillDirection?,
	fillDirectionMaxCells: number?,
	horizontalAlignment: Enum.HorizontalAlignment?,
	sortOrder: Enum.SortOrder?,
	startCorner: Enum.StartCorner?,
	verticalAlignment: Enum.VerticalAlignment?,
}
```

### `uiListLayoutProps`

```lua
export type uiListLayoutProps = hostMetadataProps<UIListLayout> & {
	fillDirection: Enum.FillDirection?,
	horizontalAlignment: Enum.HorizontalAlignment?,
	horizontalFlex: Enum.UIFlexAlignment?,
	itemLineAlignment: Enum.ItemLineAlignment?,
	padding: UDim?,
	sortOrder: Enum.SortOrder?,
	verticalAlignment: Enum.VerticalAlignment?,
	verticalFlex: Enum.UIFlexAlignment?,
	wraps: boolean?,
}
```

### `uiPaddingProps`

```lua
export type uiPaddingProps = hostMetadataProps<UIPadding> & {
	paddingBottom: UDim?,
	paddingLeft: UDim?,
	paddingRight: UDim?,
	paddingTop: UDim?,
}
```

### `uiPageLayoutProps`

```lua
export type uiPageLayoutProps = hostMetadataProps<UIPageLayout> & {
	animated: boolean?,
	circular: boolean?,
	easingDirection: Enum.EasingDirection?,
	easingStyle: Enum.EasingStyle?,
	gamepadInputEnabled: boolean?,
	padding: UDim?,
	scrollWheelInputEnabled: boolean?,
	touchInputEnabled: boolean?,
	tweenTime: number?,
}
```

### `uiScaleProps`

```lua
export type uiScaleProps = hostMetadataProps<UIScale> & {
	scale: number?,
}
```

### `uiSizeConstraintProps`

```lua
export type uiSizeConstraintProps = hostMetadataProps<UISizeConstraint> & {
	maximumSize: Vector2?,
	minimumSize: Vector2?,
}
```

### `uiStrokeProps`

```lua
export type uiStrokeProps = hostMetadataProps<UIStroke> & {
	applyStrokeMode: Enum.ApplyStrokeMode?,
	color: Color3?,
	enabled: boolean?,
	lineJoinMode: Enum.LineJoinMode?,
	thickness: number?,
	transparency: number?,
}
```

### `uiTextSizeConstraintProps`

```lua
export type uiTextSizeConstraintProps = hostMetadataProps<UITextSizeConstraint> & {
	maximumTextSize: number?,
	minimumTextSize: number?,
}
```


---


## Reactily 1.1 Module Map

Normal application code should use `src/init.luau`. The paths below describe the current implementation ownership.

| Module | Responsibility |
| --- | --- |
| `src/core/batching.luau` | Global nested-safe batching and end-of-batch work |
| `src/core/compare.luau` | Shallow comparison helpers |
| `src/core/devMode.luau` | Strict development checks |
| `src/core/lifecycle.luau` | Resource ownership and cleanup |
| `src/core/objectPool.luau` | Bounded object and Instance reuse |
| `src/core/scheduler.luau` | Idle-safe queued work |
| `src/core/signal.luau` | Typed signals and signal transforms |
| `src/core/tableUtility.luau` | Immutable table helpers |
| `src/diagnostics/diagnostics.luau` | Explicit runtime counters |
| `src/diagnostics/profiler.luau` | Component render profiling |
| `src/interface/focus.luau` | GUI focus groups |
| `src/interface/style.luau` | Style composition |
| `src/interface/theme.luau` | Typed theme state |
| `src/interface/virtualGrid.luau` | Fixed-size grid virtualization |
| `src/interface/virtualList.luau` | Fixed-size list virtualization |
| `src/interface/virtualWindow.luau` | Variable-size virtualization |
| `src/runtime/animation.luau` | Owned TweenService animations |
| `src/runtime/animationGroup.luau` | Delay, parallel, and sequence animation composition |
| `src/runtime/binding.luau` | Reactive bindings and Roblox synchronization |
| `src/runtime/hostConfig.luau` | Reactily prop/event mapping to Roblox |
| `src/runtime/lazy.luau` | Lazy component loading |
| `src/runtime/renderer.luau` | Roblox Instance creation/update/deletion |
| `src/runtime/resource.luau` | Suspense-compatible asynchronous resources |
| `src/runtime/root.luau` | Render-root lifecycle |
| `src/runtime/spring.luau` | Idle-safe spring motion |
| `src/runtime/transition.luau` | One-shot low-priority transition work |
| `src/state/atom.luau` | Atoms, computed state, history, Attributes |
| `src/state/context.luau` | Context provider/consumer state |
| `src/state/hooks.luau` | Component hooks and hook runtime |
| `src/state/store.luau` | Stores, selectors, batching, middleware |
| `src/virtual/element.luau` | Elements, typed creators, boundaries, portals |
| `src/virtual/forwardRef.luau` | Forwarded-ref component wrappers |
| `src/virtual/memo.luau` | Memoized component wrappers |
| `src/virtual/reconciler.luau` | Reconciliation, keys, Suspense, errors, deletion |


# Advanced Module Reference

Application code should normally require only the Reactily package root. These modules are intended for framework development or advanced integration.

## `src/core/lifecycle.luau`

```lua
lifecycle.addCleanup(owner, callback)
lifecycle.bindInstanceDeletion(owner, instance)
lifecycle.connect(owner, signal, callback)
lifecycle.connectNamed(owner, connections, name, signal, callback)
lifecycle.createChild(parent)
lifecycle.delete(owner)
lifecycle.deleteInstance(owner, instance)
lifecycle.deleteInstances(owner)
lifecycle.disconnect(owner, connection)
lifecycle.disconnectAll(owner)
lifecycle.getCleanupCount(owner)
lifecycle.getConnectionCount(owner)
lifecycle.getInstanceCount(owner)
lifecycle.isDeleted(owner)
lifecycle.new()
lifecycle.replaceInstance(owner, current, nextValue)
lifecycle.runCleanups(owner)
lifecycle.trackInstance(owner, instance)
```

`bindInstanceDeletion()` observes Roblox `Instance.Destroying` and deletes the Reactily owner when the Instance is externally destroyed.

## `src/core/objectPool.luau`

```lua
objectPool.instance(className, maximumSize)
objectPool.new(createObject, resetObject, deleteObject, maximumSize)
```

## `src/core/scheduler.luau`

```lua
scheduler.new()
```

## `src/core/signal.luau`

```lua
signal.distinct(source)
signal.filter(source, predicate)
signal.map(source, mapper)
signal.merge(sources)
signal.new()
signal.skip(source, amount)
signal.take(source, maximum)
```

## `src/diagnostics/diagnostics.luau`

```lua
diagnostics.new()
```

## `src/interface/focus.luau`

```lua
focus.clearSelection()
focus.new()
```

## `src/interface/style.luau`

```lua
style.apply(properties, styleValue)
style.merge(styles)
style.when(condition, styleValue)
style.without(styleValue, property)
style.withProperty(styleValue, property, value)
```

## `src/interface/theme.luau`

```lua
theme.new(initialValue)
theme.resolve(themeValue, selector)
```

## `src/interface/virtualList.luau`

```lua
virtualList.resolve(itemCount, itemSize, scrollOffset, viewportSize, overscan)
virtualList.slice(items, rangeValue)
```

## `src/runtime/animation.luau`

```lua
animation.play(instance, goals, options)
animation.tween(instance, goals, options)
```

## `src/runtime/binding.luau`

```lua
binding.attach(source, instance, propertyName)
binding.clamp(source, minimum, maximum)
binding.combine(first, second, mapper)
binding.format(source, formatter)
binding.map(source, mapper)
binding.new(initialValue)
binding.round(source, precision)
```

`binding.attach()` returns a cleanup callback that disconnects the property subscription.

## `src/runtime/hostConfig.luau`

```lua
hostConfig.getEventName(propName)
hostConfig.getPropertyName(propName)
hostConfig.isEvent(propName)
hostConfig.isProperty(propName)
```

## `src/runtime/renderer.luau`

```lua
renderer.createHost(parent, elementValue)
renderer.deleteHost(handle)
renderer.updateHost(handle, previousProps, nextProps)
```

## `src/runtime/root.luau`

```lua
root.new(parent)
```

## `src/state/atom.luau`

```lua
atom.computed(source, selector)
atom.fromAttribute(instance, attributeName, defaultValue)
atom.history(initialValue, limit)
atom.new(initialValue)
```

## `src/state/hooks.luau`

Public hook implementations plus framework render-context functions:

```lua
hooks.beginRender(context)
hooks.deleteContext(context)
hooks.endRender(context, didComplete)
hooks.flushEffects(context)
hooks.newContext(requestRender)
```

Application code should use the hooks re-exported by `Reactily`.

## `src/state/store.luau`

```lua
store.new(initialState)
```

## `src/virtual/element.luau`

Contains the virtual element union, prop contracts, and typed element constructors documented above.

## `src/virtual/reconciler.luau`

```lua
reconciler.delete(node)
reconciler.reconcile(parent, currentNode, nextElement, options)
```

---

# Complete Examples

## Typed counter

```lua
local Reactily = require(path.Reactily)

local function counter(): Reactily.element
	local count, controls = Reactily.useCounter(0)

	return Reactily.createFrame({
		size = UDim2.fromOffset(300, 140),
		backgroundColor3 = Color3.fromRGB(27, 27, 31),
		borderSizePixel = 0,
	}, {
		Reactily.createUICorner({
			cornerRadius = UDim.new(0, 10),
		}),

		Reactily.createTextButton({
			size = UDim2.fromScale(1, 1),
			backgroundTransparency = 1,
			text = `Count: {count}`,
			textColor3 = Color3.new(1, 1, 1),
			textSize = 28,

			onActivated = function()
				controls.increment()
			end,
		}),
	})
end

local root = Reactily.createRoot(playerGui)

root.render(
	Reactily.createComponent(counter, {})
)
```

## Store-driven page state

```lua
local Reactily = require(path.Reactily)

type appState = {
	page: "Home" | "Effects" | "Position",
	selectedFixture: number?,
}

local app = Reactily.createStore<appState>({
	page = "Home",
	selectedFixture = nil,
})

local page = app.select(function(state: appState)
	return state.page
end)

page.subscribe(function(change)
	print(`Page: {change.previous} -> {change.current}`)
end)

app.update(function(previous: appState): appState
	return {
		page = "Effects",
		selectedFixture = previous.selectedFixture,
	}
end)
```

## Position editor history

```lua
local Reactily = require(path.Reactily)

type position = {
	pan: number,
	tilt: number,
}

local currentPosition = Reactily.createHistoryAtom<position>(
	{
		pan = 0,
		tilt = 0,
	},
	100
)

currentPosition.set({
	pan = 30,
	tilt = -15,
})

currentPosition.undo()
currentPosition.redo()
```

## Modal portal

```lua
local overlay = Reactily.createPortal(screenGui, {
	Reactily.createFrame({
		key = "overlay",
		size = UDim2.fromScale(1, 1),
		backgroundColor3 = Color3.new(0, 0, 0),
		backgroundTransparency = .4,
	}, {
		Reactily.createFrame({
			anchorPoint = Vector2.new(.5, .5),
			position = UDim2.fromScale(.5, .5),
			size = UDim2.fromOffset(500, 320),
		}),
	}),
}, "settings-modal")
```

## Virtualized fixture list

```lua
local range = Reactily.resolveVirtualList(
	#fixtures,
	36,
	scrollingFrame.CanvasPosition.Y,
	scrollingFrame.AbsoluteWindowSize.Y,
	4
)

local children: {Reactily.element} = {}

for index = range.first, range.last do
	local fixture = fixtures[index]

	children[#children + 1] = Reactily.createTextButton({
		key = tostring(fixture.id),
		position = UDim2.fromOffset(0, (index - 1) * 36),
		size = UDim2.new(1, 0, 0, 36),
		text = fixture.name,
	})
end
```

## Attribute-backed component state

```lua
type fixtureToggleProps = {
	fixture: Model,
}

local function fixtureToggle(props: fixtureToggleProps): Reactily.element
	local enabled, setEnabled = Reactily.useAttribute(
		props.fixture,
		"enabled",
		true
	)

	return Reactily.createTextButton({
		text = if enabled then "Enabled" else "Disabled",

		onActivated = function()
			setEnabled(not enabled)
		end,
	})
end
```

## Owned Tween

```lua
local animation = Reactily.playTween(
	panel,
	{
		Position = UDim2.fromScale(.5, .5),
		BackgroundTransparency = 0,
	},
	{
		time = .25,
		easingStyle = Enum.EasingStyle.Quad,
		easingDirection = Enum.EasingDirection.Out,
	}
)

animation.onCompleted(function(playbackState)
	if playbackState ~= Enum.PlaybackState.Completed then return end

	animation.delete()
end)
```

---

## Versioning

Current version:

```text
1.0.0
```

Runtime access:

```lua
local version = Reactily.getVersion()
```

---

## Final Notes

The supported package contract is `src/init.luau`. Prefer that API unless you are extending Reactily itself.

Reactily's core runtime contract is built around typed class-specific creators, stable hook order, keyed reconciliation, explicit `.delete()` ownership, change-only updates, and no permanent self-generated frame loop while the framework is idle.

---

# All References

This final section is the consolidated Reactily reference index. It is intentionally placed at the end of the documentation so the full guide can be read normally while every callable API remains available in one lookup section.

## Public Package Reference

### Package

```lua
Reactily.getVersion(): string
Reactily.new(parent: Instance): Reactily.root
Reactily.createRoot(parent: Instance): Reactily.root
```

### Virtual Tree

```lua
Reactily.createElement(
	className: string,
	props: {[string]: any}?,
	children: {Reactily.element}?
): Reactily.element

Reactily.createComponent<P>(
	componentValue: Reactily.component<P>,
	props: P,
	children: {Reactily.element}?,
	key: string?
): Reactily.element

Reactily.createFragment(
	children: {Reactily.element},
	key: string?
): Reactily.element

Reactily.createPortal(
	target: Instance,
	children: {Reactily.element},
	key: string?
): Reactily.element
```

### Typed Roblox Creators

```lua
Reactily.createBillboardGui(props: Reactily.billboardGuiProps?, children: {Reactily.element}?): Reactily.element
Reactily.createCanvasGroup(props: Reactily.canvasGroupProps?, children: {Reactily.element}?): Reactily.element
Reactily.createFrame(props: Reactily.frameProps?, children: {Reactily.element}?): Reactily.element
Reactily.createImageButton(props: Reactily.imageButtonProps?, children: {Reactily.element}?): Reactily.element
Reactily.createImageLabel(props: Reactily.imageLabelProps?, children: {Reactily.element}?): Reactily.element
Reactily.createScreenGui(props: Reactily.screenGuiProps?, children: {Reactily.element}?): Reactily.element
Reactily.createScrollingFrame(props: Reactily.scrollingFrameProps?, children: {Reactily.element}?): Reactily.element
Reactily.createSurfaceGui(props: Reactily.surfaceGuiProps?, children: {Reactily.element}?): Reactily.element
Reactily.createTextBox(props: Reactily.textBoxProps?, children: {Reactily.element}?): Reactily.element
Reactily.createTextButton(props: Reactily.textButtonProps?, children: {Reactily.element}?): Reactily.element
Reactily.createTextLabel(props: Reactily.textLabelProps?, children: {Reactily.element}?): Reactily.element
Reactily.createVideoFrame(props: Reactily.videoFrameProps?, children: {Reactily.element}?): Reactily.element
Reactily.createViewportFrame(props: Reactily.viewportFrameProps?, children: {Reactily.element}?): Reactily.element

Reactily.createUIAspectRatioConstraint(props: Reactily.uiAspectRatioConstraintProps?): Reactily.element
Reactily.createUICorner(props: Reactily.uiCornerProps?): Reactily.element
Reactily.createUIGradient(props: Reactily.uiGradientProps?): Reactily.element
Reactily.createUIGridLayout(props: Reactily.uiGridLayoutProps?): Reactily.element
Reactily.createUIListLayout(props: Reactily.uiListLayoutProps?): Reactily.element
Reactily.createUIPadding(props: Reactily.uiPaddingProps?): Reactily.element
Reactily.createUIPageLayout(props: Reactily.uiPageLayoutProps?): Reactily.element
Reactily.createUIScale(props: Reactily.uiScaleProps?): Reactily.element
Reactily.createUISizeConstraint(props: Reactily.uiSizeConstraintProps?): Reactily.element
Reactily.createUIStroke(props: Reactily.uiStrokeProps?): Reactily.element
Reactily.createUITextSizeConstraint(props: Reactily.uiTextSizeConstraintProps?): Reactily.element
```

## Hooks Reference

```lua
Reactily.useState<T>(
	initialValue: T
): (T, Reactily.stateSetter<T>)

Reactily.useReducer<S, A>(
	reducer: (stateValue: S, action: A) -> S,
	initialState: S
): (S, Reactily.reducerDispatch<A>)

Reactily.useRef<T>(
	initialValue: T
): Reactily.ref<T>

Reactily.useMemo<T>(
	factory: () -> T,
	dependencies: {any}?
): T

Reactily.useCallback<T>(
	callback: T,
	dependencies: {any}?
): T

Reactily.useEffect(
	callback: () -> (() -> ())?,
	dependencies: {any}?
)

Reactily.usePrevious<T>(
	value: T
): T?

Reactily.useToggle(
	initialValue: boolean?
): (
	boolean,
	() -> (),
	(value: boolean) -> ()
)

Reactily.useBoolean(
	initialValue: boolean?
): (
	boolean,
	() -> (),
	() -> (),
	() -> ()
)

Reactily.useCounter(
	initialValue: number?
): (
	number,
	Reactily.counterControls
)

Reactily.useDebouncedValue<T>(
	value: T,
	delaySeconds: number
): T

Reactily.useAttribute<T>(
	instance: Instance,
	attributeName: string,
	defaultValue: T
): (
	T,
	(value: T) -> ()
)
```

## Atom Reference

```lua
Reactily.createAtom<T>(
	initialValue: T
): Reactily.atom<T>

Reactily.createComputed<A, B>(
	source: Reactily.atom<A>,
	selectorFunction: (value: A) -> B
): Reactily.computed<B>

Reactily.createHistoryAtom<T>(
	initialValue: T,
	limit: number
): Reactily.historyAtom<T>

Reactily.createAttributeAtom<T>(
	instance: Instance,
	attributeName: string,
	defaultValue: T
): Reactily.atom<T>
```

### `atom<T>`

```lua
atom.get(): T
atom.set(value: T): boolean
atom.update(updater: (previous: T) -> T): boolean
atom.subscribe(callback: (change: Reactily.atomChange<T>) -> ()): Reactily.connection
atom.isDeleted(): boolean
atom.delete(): boolean
```

### `computed<T>`

```lua
computed.get(): T
computed.subscribe(callback: (change: Reactily.atomChange<T>) -> ()): Reactily.connection
computed.isDeleted(): boolean
computed.delete(): boolean
```

### `historyAtom<T>`

```lua
historyAtom.get(): T
historyAtom.set(value: T): boolean
historyAtom.update(updater: (previous: T) -> T): boolean
historyAtom.subscribe(callback: (change: Reactily.atomChange<T>) -> ()): Reactily.connection

historyAtom.canUndo(): boolean
historyAtom.canRedo(): boolean
historyAtom.undo(): boolean
historyAtom.redo(): boolean
historyAtom.clearHistory()
historyAtom.getPastCount(): number
historyAtom.getFutureCount(): number

historyAtom.isDeleted(): boolean
historyAtom.delete(): boolean
```

## Store Reference

```lua
Reactily.createStore<T>(
	initialState: T
): Reactily.store<T>
```

### `store<T>`

```lua
store.get(): T
store.set(state: T): boolean
store.update(updater: (state: T) -> T): boolean
store.reset(): boolean

store.subscribe(
	callback: (change: {
		current: T,
		previous: T,
	}) -> ()
): Reactily.connection

store.select<R>(
	selectorFunction: (state: T) -> R
): Reactily.selector<R>

store.batch(callback: () -> ())

store.isDeleted(): boolean
store.delete(): boolean
```

### `selector<T>`

```lua
selector.get(): T

selector.subscribe(
	callback: (change: {
		current: T,
		previous: T,
	}) -> ()
): Reactily.connection

selector.isDeleted(): boolean
selector.delete(): boolean
```

## Binding Reference

```lua
Reactily.createBinding<T>(
	initialValue: T
): Reactily.binding<T>

Reactily.mapBinding<A, B>(
	source: Reactily.binding<A>,
	mapper: (value: A) -> B
): Reactily.binding<B>

Reactily.combineBindings<A, B, R>(
	first: Reactily.binding<A>,
	second: Reactily.binding<B>,
	mapper: (firstValue: A, secondValue: B) -> R
): Reactily.binding<R>

Reactily.clampBinding(
	source: Reactily.binding<number>,
	minimum: number,
	maximum: number
): Reactily.binding<number>

Reactily.roundBinding(
	source: Reactily.binding<number>,
	precision: number
): Reactily.binding<number>

Reactily.formatBinding<T>(
	source: Reactily.binding<T>,
	formatter: (value: T) -> string
): Reactily.binding<string>
```

### `binding<T>`

```lua
binding.get(): T
binding.set(value: T): boolean
binding.subscribe(callback: (change: Reactily.bindingChange<T>) -> ()): Reactily.connection
binding.isDeleted(): boolean
binding.delete(): boolean
```

## Signal Reference

```lua
Reactily.createSignal<T>(): Reactily.signal<T>

Reactily.mapSignal<A, B>(
	source: Reactily.signal<A>,
	mapper: (value: A) -> B
): Reactily.signal<B>

Reactily.filterSignal<T>(
	source: Reactily.signal<T>,
	predicate: (value: T) -> boolean
): Reactily.signal<T>

Reactily.distinctSignal<T>(
	source: Reactily.signal<T>
): Reactily.signal<T>

Reactily.mergeSignals<T>(
	sources: {Reactily.signal<T>}
): Reactily.signal<T>

Reactily.skipSignal<T>(
	source: Reactily.signal<T>,
	amount: number
): Reactily.signal<T>

Reactily.takeSignal<T>(
	source: Reactily.signal<T>,
	maximum: number
): Reactily.signal<T>
```

### `signal<T>`

```lua
signal.connect(callback: (value: T) -> ()): Reactily.connection
signal.once(callback: (value: T) -> ()): Reactily.connection
signal.fire(value: T)
signal.getListenerCount(): number
signal.isDeleted(): boolean
signal.delete(): boolean
```

### `connection`

```lua
connection.connected: boolean
connection.disconnect(): boolean
```

## Root Reference

### `root`

```lua
root.render(elementValue: Reactily.element?)
root.flush()

root.batch(callback: () -> ())

root.suspend(): boolean
root.resume(): boolean
root.isSuspended(): boolean

root.getElement(): Reactily.element?
root.getParent(): Instance

root.isDeleted(): boolean
root.delete(): boolean
```

## Theme Reference

```lua
Reactily.createTheme<T>(
	initialValue: T
): Reactily.theme<T>

Reactily.resolveTheme<T, R>(
	themeValue: Reactily.theme<T>,
	selectorFunction: (tokens: T) -> R
): R
```

### `theme<T>`

```lua
theme.get(): T
theme.set(value: T): boolean
theme.update(updater: (value: T) -> T): boolean
theme.subscribe(callback: (value: T) -> ()): Reactily.connection
theme.isDeleted(): boolean
theme.delete(): boolean
```

## Style Reference

```lua
Reactily.createStyle(
	styles: {Reactily.style}
): Reactily.style

Reactily.applyStyle<T>(
	properties: T,
	styleValue: Reactily.style
): T
```

Advanced style helpers:

```lua
style.merge(styles)
style.when(condition, styleValue)
style.withProperty(styleValue, property, value)
style.without(styleValue, property)
style.apply(properties, styleValue)
```

## Animation Reference

```lua
Reactily.createTween(
	instance: Instance,
	goals: {[string]: any},
	options: Reactily.tweenOptions
): Reactily.animation

Reactily.playTween(
	instance: Instance,
	goals: {[string]: any},
	options: Reactily.tweenOptions
): Reactily.animation
```

### `animation`

```lua
animation.tween: Tween
animation.play()
animation.cancel(): boolean

animation.onCompleted(
	callback: (playbackState: Enum.PlaybackState) -> ()
): RBXScriptConnection

animation.isDeleted(): boolean
animation.delete(): boolean
```

### `tweenOptions`

```lua
type tweenOptions = {
	delayTime: number?,
	easingDirection: Enum.EasingDirection?,
	easingStyle: Enum.EasingStyle?,
	repeatCount: number?,
	reverses: boolean?,
	time: number,
}
```

## Focus Reference

```lua
Reactily.createFocusGroup(): Reactily.focusGroup
Reactily.clearFocus()
```

### `focusGroup`

```lua
focusGroup.add(object: GuiObject): boolean
focusGroup.remove(object: GuiObject): boolean
focusGroup.clear()
focusGroup.focusFirst(): boolean
focusGroup.focusLast(): boolean
focusGroup.getItems(): {GuiObject}
focusGroup.isDeleted(): boolean
focusGroup.delete(): boolean
```

## Virtual List Reference

```lua
Reactily.resolveVirtualList(
	itemCount: number,
	itemSize: number,
	scrollOffset: number,
	viewportSize: number,
	overscan: number?
): Reactily.virtualRange

Reactily.sliceVirtualList<T>(
	items: {T},
	rangeValue: Reactily.virtualRange
): {T}
```

### `virtualRange`

```lua
type virtualRange = {
	first: number,
	last: number,
	offset: number,
	totalSize: number,
}
```

## Object Pool Reference

```lua
Reactily.createObjectPool<T>(
	createObject: () -> T,
	resetObject: (object: T) -> (),
	deleteObject: (object: T) -> (),
	maximumSize: number
): Reactily.objectPool<T>

Reactily.createInstancePool(
	className: string,
	maximumSize: number
): Reactily.objectPool<Instance>
```

### `objectPool<T>`

```lua
objectPool.acquire(): T
objectPool.release(object: T): boolean
objectPool.clear()
objectPool.getAvailableCount(): number
objectPool.getCreatedCount(): number
objectPool.isDeleted(): boolean
objectPool.delete(): boolean
```

## Scheduler Reference

```lua
Reactily.createScheduler(): Reactily.scheduler
```

### `scheduler`

```lua
scheduler.enqueue(callback: () -> ()): number
scheduler.enqueueKeyed(key: string, callback: () -> ()): number

scheduler.cancel(taskId: number): boolean
scheduler.cancelKey(key: string): boolean

scheduler.isPending(key: string): boolean
scheduler.getPendingCount(): number

scheduler.flush()
scheduler.clear()

scheduler.isDeleted(): boolean
scheduler.delete(): boolean
```

## Diagnostics Reference

```lua
Reactily.createDiagnostics(): Reactily.diagnostics
```

### `diagnostics`

```lua
diagnostics.increment(name: string, amount: number?): number
diagnostics.get(name: string): number
diagnostics.reset(name: string): boolean
diagnostics.resetAll()
diagnostics.snapshot(): {[string]: number}
diagnostics.isDeleted(): boolean
diagnostics.delete(): boolean
```

## Lifecycle Reference

```lua
Reactily.createLifecycleOwner(): Reactily.lifecycleOwner
```

Advanced lifecycle module API:

```lua
lifecycle.new(): lifecycleOwner

lifecycle.connect(
	ownerValue,
	signal,
	callback
): RBXScriptConnection

lifecycle.connectNamed(
	ownerValue,
	connections,
	name,
	signal,
	callback
): RBXScriptConnection

lifecycle.disconnect(
	ownerValue,
	connection
): boolean

lifecycle.disconnectAll(ownerValue)

lifecycle.trackInstance(ownerValue, instance)
lifecycle.replaceInstance(ownerValue, current, nextValue)
lifecycle.deleteInstance(ownerValue, instance): boolean
lifecycle.deleteInstances(ownerValue)

lifecycle.addCleanup(ownerValue, callback)
lifecycle.runCleanups(ownerValue)

lifecycle.createChild(parent)
lifecycle.bindInstanceDeletion(ownerValue, instance)

lifecycle.getConnectionCount(ownerValue): number
lifecycle.getInstanceCount(ownerValue): number
lifecycle.getCleanupCount(ownerValue): number

lifecycle.isDeleted(ownerValue): boolean
lifecycle.delete(ownerValue): boolean
```

## Host Metadata Reference

All supported host creators inherit Reactily metadata where applicable:

```lua
key: string?
ref: ((instance: T?) -> ())?
attributes: {[string]: Reactily.attributeValue}?
tags: {string}?
```

### `attributeValue`

```lua
type attributeValue =
	boolean
	| BrickColor
	| CFrame
	| Color3
	| ColorSequence
	| Font
	| NumberRange
	| NumberSequence
	| Rect
	| string
	| number
	| UDim
	| UDim2
	| Vector2
	| Vector3
```

## Common GUI Event Reference

```lua
onAncestryChanged: ((child: Instance, parent: Instance?) -> ())?
onChanged: ((property: string) -> ())?
onInputBegan: ((input: InputObject) -> ())?
onInputChanged: ((input: InputObject) -> ())?
onInputEnded: ((input: InputObject) -> ())?
onMouseEnter: (() -> ())?
onMouseLeave: (() -> ())?
```

Button creators additionally support button-specific events such as:

```lua
onActivated: ((input: InputObject, clickCount: number) -> ())?
onMouseButton1Click: (() -> ())?
onMouseButton1Down: ((x: number, y: number) -> ())?
onMouseButton1Up: ((x: number, y: number) -> ())?
onMouseButton2Click: (() -> ())?
onMouseButton2Down: ((x: number, y: number) -> ())?
onMouseButton2Up: ((x: number, y: number) -> ())?
```

## Module Path Reference

| Module | Responsibility |
| --- | --- |
| `src/init.luau` | Public Reactily API |
| `src/core/lifecycle.luau` | Resource ownership and deletion |
| `src/core/objectPool.luau` | Bounded object and Instance reuse |
| `src/core/scheduler.luau` | Idle-safe queued rendering/work |
| `src/core/signal.luau` | Typed signals and derived signal operators |
| `src/diagnostics/diagnostics.luau` | Explicit runtime counters |
| `src/interface/focus.luau` | GUI focus groups |
| `src/interface/style.luau` | Style table composition |
| `src/interface/theme.luau` | Typed theme state |
| `src/interface/virtualList.luau` | Fixed-size list virtualization |
| `src/runtime/animation.luau` | Owned TweenService animations |
| `src/runtime/binding.luau` | Reactive bindings and transforms |
| `src/runtime/hostConfig.luau` | Reactily prop/event → Roblox mapping |
| `src/runtime/renderer.luau` | Roblox Instance creation/update/deletion |
| `src/runtime/root.luau` | Render root lifecycle |
| `src/state/atom.luau` | Atoms, computed state, history, Attributes |
| `src/state/hooks.luau` | Component hooks and hook runtime |
| `src/state/store.luau` | Stores, selectors, batches |
| `src/virtual/element.luau` | Element types and typed creators |
| `src/virtual/reconciler.luau` | Reconciliation, keys, portals, deletion |

## Lifecycle Naming Reference

Reactily-owned lifecycle terminology:

```lua
delete
isDeleted
deleteInstance
deleteInstances
deleteObject
deleteContext
deleteHost
```

Roblox-owned lifecycle names remain Roblox-owned:

```lua
instance:Destroy()
tween:Destroy()
instance.Destroying
connection:Disconnect()
```

Reactily never renames external Roblox contracts.

## Final Reference Rule

For normal application code, treat `src/init.luau` as the supported package contract.

Use the advanced module APIs only when extending Reactily itself or when a framework-level integration genuinely requires lower-level ownership, scheduling, rendering, or host configuration access.

---

---

# Detailed Full API Reference

This is the exhaustive callable reference. Each entry includes the actual Luau signature, parameters/arguments, return value, purpose, and a usage example.

## `Reactily.*` Public API

### `Reactily.applyStyle`

Applies a style table onto a cloned typed props table.

#### Signature

```lua
Reactily.applyStyle<T>(properties: T, styleValue: style): T
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `properties` | `T` | Yes | Typed props table that receives the supplied Reactily style values. |
| `styleValue` | `style` | Yes | Reactily style table to apply. |

#### Returns

`T`.

#### Usage

```lua
local props = Reactily.applyStyle({
	size = UDim2.fromOffset(200, 80),
}, {
	backgroundTransparency = .2,
})
```

### `Reactily.clampBinding`

Creates a derived numeric binding clamped between `minimum` and `maximum`.

#### Signature

```lua
Reactily.clampBinding(
	source: binding<number>,
	minimum: number,
	maximum: number
): binding<number>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `binding<number>` | Yes | Source Reactily atom, binding, or signal. |
| `minimum` | `number` | Yes | Minimum allowed numeric value. |
| `maximum` | `number` | Yes | Maximum allowed value or maximum number of signal emissions to forward. |

#### Returns

A `binding<number>`.

#### Usage

```lua
local safeIntensity = Reactily.clampBinding(intensity, 0, 1)
```

### `Reactily.clearFocus`

Clears Roblox `GuiService.SelectedObject`.

#### Signature

```lua
Reactily.clearFocus()
```

#### Parameters

_No parameters._

#### Returns

No value.

#### Usage

```lua
Reactily.clearFocus()
```

### `Reactily.combineBindings`

Creates a derived binding from two source bindings.

#### Signature

```lua
Reactily.combineBindings<A, B, R>(
	first: binding<A>,
	second: binding<B>,
	mapper: (firstValue: A, secondValue: B) -> R
): binding<R>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `first` | `binding<A>` | Yes | First source binding. |
| `second` | `binding<B>` | Yes | Second source binding. |
| `mapper` | `(firstValue: A, secondValue: B) -> R` | Yes | Function that transforms one or more source values into the derived value. |

#### Returns

A `binding<R>`.

#### Usage

```lua
local point = Reactily.combineBindings(pan, tilt, function(panValue, tiltValue)
	return Vector2.new(panValue, tiltValue)
end)
```

### `Reactily.createAttributeAtom`

Creates an atom synchronized bidirectionally with one Roblox Attribute.

#### Signature

```lua
Reactily.createAttributeAtom<T>(
	instance: Instance,
	attributeName: string,
	defaultValue: T
): atom<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `instance` | `Instance` | Yes | Roblox Instance used by the requested Reactily helper. |
| `attributeName` | `string` | Yes | Roblox Attribute name owned or observed by this Reactily state helper. |
| `defaultValue` | `T` | Yes | Fallback value used when the Roblox Attribute currently has no value. |

#### Returns

A `atom<T>`.

#### Usage

```lua
local enabled = Reactily.createAttributeAtom(fixture, "enabled", true)
```

### `Reactily.createAtom`

Creates standalone change-only typed state.

#### Signature

```lua
Reactily.createAtom<T>(initialValue: T): atom<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `T` | Yes | Initial typed value. |

#### Returns

A `atom<T>`.

#### Usage

```lua
local bpm = Reactily.createAtom(.7)
```

### `Reactily.createBillboardGui`

Creates a typed virtual `BillboardGui` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createBillboardGui(props: billboardGuiProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `billboardGuiProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createBillboardGui({
	size = UDim2.fromOffset(240, 80),
	alwaysOnTop = true,
}, {
	Reactily.createTextLabel({
		size = UDim2.fromScale(1, 1),
		text = "Fixture",
	}),
})
```

### `Reactily.createBinding`

Creates a standalone reactive binding.

#### Signature

```lua
Reactily.createBinding<T>(initialValue: T): binding<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `T` | Yes | Initial typed value. |

#### Returns

A `binding<T>`.

#### Usage

```lua
local intensity = Reactily.createBinding(.5)
```

### `Reactily.createCanvasGroup`

Creates a typed virtual `CanvasGroup` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createCanvasGroup(props: canvasGroupProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `canvasGroupProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createCanvasGroup({
	size = UDim2.fromOffset(300, 180),
	groupTransparency = 0,
})
```

### `Reactily.createComponent`

Creates a virtual function-component element.

#### Signature

```lua
Reactily.createComponent<P>(
	componentValue: component<P>,
	props: P,
	children: {element}?,
	key: string?
): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `componentValue` | `component<P>` | Yes | Typed Reactily function component to render. |
| `props` | `P` | Yes | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |
| `key` | `string?` | No | Optional stable identity key used by reconciliation. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createComponent(counter, {})
```

### `Reactily.createComputed`

Creates read-only derived atom state from a source atom.

#### Signature

```lua
Reactily.createComputed<A, B>(
	source: atom<A>,
	selectorFunction: (value: A) -> B
): computed<B>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `atom<A>` | Yes | Source Reactily atom, binding, or signal. |
| `selectorFunction` | `(value: A) -> B` | Yes | Function that derives a selected/computed value from the source. |

#### Returns

A read-only derived `computed<B>`.

#### Usage

```lua
local label = Reactily.createComputed(bpm, function(value)
	return string.format("%.2f BPM", value)
end)
```

### `Reactily.createDiagnostics`

Creates explicit runtime counters with no background polling.

#### Signature

```lua
Reactily.createDiagnostics(): diagnostics
```

#### Parameters

_No parameters._

#### Returns

A diagnostics counter owner.

#### Usage

```lua
local diagnostics = Reactily.createDiagnostics()
diagnostics.increment("renders")
```

### `Reactily.createElement`

Creates a generic Roblox host element. Prefer a typed creator when one exists.

#### Signature

```lua
Reactily.createElement(
	className: string,
	props: elementModule.genericProps?,
	children: {element}?
): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `className` | `string` | Yes | Roblox Instance class name to create or pool. |
| `props` | `elementModule.genericProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createElement("Frame", {
	size = UDim2.fromOffset(300, 180),
})
```

### `Reactily.createFocusGroup`

Creates a focus collection for keyboard/controller GUI selection.

#### Signature

```lua
Reactily.createFocusGroup(): focusGroup
```

#### Parameters

_No parameters._

#### Returns

A GUI focus group.

#### Usage

```lua
local group = Reactily.createFocusGroup()
group.add(playButton)
group.focusFirst()
```

### `Reactily.createFragment`

Groups children without creating a Roblox host Instance.

#### Signature

```lua
Reactily.createFragment(children: {element}, key: string?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `children` | `{element}` | Yes | Optional child Reactily elements rendered beneath this element/component. |
| `key` | `string?` | No | Optional stable identity key used by reconciliation. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local fragment = Reactily.createFragment({
	firstElement,
	secondElement,
}, "group")
```

### `Reactily.createFrame`

Creates a typed virtual `Frame` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createFrame(props: frameProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `frameProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createFrame({
	size = UDim2.fromOffset(400, 240),
	backgroundColor3 = Color3.fromRGB(30, 30, 34),
	borderSizePixel = 0,
})
```

### `Reactily.createHistoryAtom`

Creates an atom with bounded undo/redo history.

#### Signature

```lua
Reactily.createHistoryAtom<T>(initialValue: T, limit: number): historyAtom<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `T` | Yes | Initial typed value. |
| `limit` | `number` | Yes | Maximum number of undo-history entries retained. Must be greater than zero. |

#### Returns

A `historyAtom<T>` with undo/redo history.

#### Usage

```lua
local position = Reactily.createHistoryAtom(Vector2.zero, 100)
position.set(Vector2.new(20, 10))
position.undo()
```

### `Reactily.createImageButton`

Creates a typed virtual `ImageButton` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createImageButton(props: imageButtonProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `imageButtonProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createImageButton({
	size = UDim2.fromOffset(64, 64),
	image = "rbxassetid://123456789",
	onActivated = function()
		print("clicked")
	end,
})
```

### `Reactily.createImageLabel`

Creates a typed virtual `ImageLabel` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createImageLabel(props: imageLabelProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `imageLabelProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createImageLabel({
	size = UDim2.fromOffset(128, 128),
	image = "rbxassetid://123456789",
})
```

### `Reactily.createInstancePool`

Creates a bounded reusable pool for Roblox Instances of one class.

#### Signature

```lua
Reactily.createInstancePool(className: string, maximumSize: number): objectPool<Instance>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `className` | `string` | Yes | Roblox Instance class name to create or pool. |
| `maximumSize` | `number` | Yes | Maximum number of released objects retained by the pool. |

#### Returns

A bounded `objectPool<Instance>`.

#### Usage

```lua
local pool = Reactily.createInstancePool("Frame", 64)
local frame = pool.acquire()
pool.release(frame)
```

### `Reactily.createLifecycleOwner`

Creates a low-level owner record for connections, Instances, and cleanups.

#### Signature

```lua
Reactily.createLifecycleOwner(): lifecycleOwner
```

#### Parameters

_No parameters._

#### Returns

A low-level Reactily lifecycle owner record.

#### Usage

```lua
local owner = Reactily.createLifecycleOwner()
```

### `Reactily.createObjectPool`

Creates a generic bounded object pool with explicit reset and final cleanup.

#### Signature

```lua
Reactily.createObjectPool<T>(
	createObject: () -> T,
	resetObject: (object: T) -> (),
	deleteObject: (object: T) -> (),
	maximumSize: number
): objectPool<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `createObject` | `() -> T,
	resetObject: (object: T) -> (),
	deleteObject: (object: T) -> (),
	maximumSize: number` | Yes | Function used to allocate a new pooled object when no reusable object is available. |

#### Returns

A bounded `objectPool<T>`.

#### Usage

```lua
local pool = Reactily.createObjectPool(
	function()
		return {}
	end,
	table.clear,
	table.clear,
	64
)
```

### `Reactily.createPortal`

Creates a virtual portal that reconciles children into another Roblox target.

#### Signature

```lua
Reactily.createPortal(target: Instance, children: {element}, key: string?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `target` | `Instance` | Yes | Roblox Instance that receives portal children. |
| `children` | `{element}` | Yes | Optional child Reactily elements rendered beneath this element/component. |
| `key` | `string?` | No | Optional stable identity key used by reconciliation. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local portal = Reactily.createPortal(overlayGui, {
	modalElement,
}, "modal")
```

### `Reactily.createRoot`

Creates a Reactily render root under a Roblox parent.

#### Signature

```lua
Reactily.createRoot(parent: Instance): root
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `parent` | `Instance` | Yes | Roblox Instance that receives the root's rendered host tree. |

#### Returns

A Reactily render root.

#### Usage

```lua
local root = Reactily.createRoot(playerGui)
root.render(appElement)
```

### `Reactily.createScheduler`

Creates Reactily's idle-safe one-shot work scheduler.

#### Signature

```lua
Reactily.createScheduler(): scheduler
```

#### Parameters

_No parameters._

#### Returns

A Reactily scheduler.

#### Usage

```lua
local scheduler = Reactily.createScheduler()
scheduler.enqueue(function()
	print("scheduled")
end)
```

### `Reactily.createScreenGui`

Creates a typed virtual `ScreenGui` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createScreenGui(props: screenGuiProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `screenGuiProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createScreenGui({
	name = "Interface",
	resetOnSpawn = false,
}, {
	Reactily.createFrame({
		size = UDim2.fromScale(1, 1),
	}),
})
```

### `Reactily.createScrollingFrame`

Creates a typed virtual `ScrollingFrame` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createScrollingFrame(props: scrollingFrameProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `scrollingFrameProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createScrollingFrame({
	size = UDim2.fromOffset(400, 500),
	canvasSize = UDim2.fromOffset(0, 1200),
	scrollBarThickness = 8,
})
```

### `Reactily.createSignal`

Creates a typed Reactily signal.

#### Signature

```lua
Reactily.createSignal<T>(): signal<T>
```

#### Parameters

_No parameters._

#### Returns

A `signal<T>`.

#### Usage

```lua
local selected = Reactily.createSignal<number>()
selected.connect(print)
selected.fire(5)
```

### `Reactily.createStore`

Creates structured external state with subscriptions, selectors, and batching.

#### Signature

```lua
Reactily.createStore<T>(initialState: T): store<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialState` | `T` | Yes | Initial typed state value. |

#### Returns

A `store<T>`.

#### Usage

```lua
local store = Reactily.createStore({
	page = "Home",
})
```

### `Reactily.createStyle`

Merges ordered style tables into one new style.

#### Signature

```lua
Reactily.createStyle(styles: {style}): style
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `styles` | `{style}` | Yes | Ordered style tables. Later entries overwrite earlier properties. |

#### Returns

A new merged Reactily style table.

#### Usage

```lua
local styleValue = Reactily.createStyle({
	baseStyle,
	selectedStyle,
})
```

### `Reactily.createSurfaceGui`

Creates a typed virtual `SurfaceGui` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createSurfaceGui(props: surfaceGuiProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `surfaceGuiProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createSurfaceGui({
	adornee = panelPart,
	pixelsPerStud = 100,
})
```

### `Reactily.createTextBox`

Creates a typed virtual `TextBox` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createTextBox(props: textBoxProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `textBoxProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createTextBox({
	size = UDim2.fromOffset(280, 48),
	placeholderText = "Search...",
	text = "",
})
```

### `Reactily.createTextButton`

Creates a typed virtual `TextButton` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createTextButton(props: textButtonProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `textButtonProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createTextButton({
	size = UDim2.fromOffset(220, 56),
	text = "Continue",
	onActivated = function()
		print("Continue")
	end,
})
```

### `Reactily.createTextLabel`

Creates a typed virtual `TextLabel` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createTextLabel(props: textLabelProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `textLabelProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createTextLabel({
	size = UDim2.fromOffset(300, 50),
	text = "Reactily",
	textSize = 28,
})
```

### `Reactily.createTheme`

Creates change-only typed theme token state.

#### Signature

```lua
Reactily.createTheme<T>(initialValue: T): theme<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `T` | Yes | Initial typed value. |

#### Returns

A `theme<T>`.

#### Usage

```lua
local theme = Reactily.createTheme({
	accent = Color3.fromRGB(80, 120, 255),
})
```

### `Reactily.createTween`

Creates an owned TweenService animation without playing it immediately.

#### Signature

```lua
Reactily.createTween(
	instance: Instance,
	goals: {[string]: any},
	options: tweenOptions
): animation
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `instance` | `Instance` | Yes | Roblox Instance used by the requested Reactily helper. |
| `goals` | `{[string]: any}` | Yes | Roblox TweenService goal property table. |
| `options` | `tweenOptions` | Yes | Typed Tween configuration. |

#### Returns

An owned Reactily animation wrapper.

#### Usage

```lua
local animation = Reactily.createTween(frame, {
	BackgroundTransparency = 0,
}, {
	time = .2,
})
animation.play()
```

### `Reactily.createUIAspectRatioConstraint`

Creates a typed virtual `UIAspectRatioConstraint` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUIAspectRatioConstraint(props: uiAspectRatioConstraintProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiAspectRatioConstraintProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local constraint = Reactily.createUIAspectRatioConstraint({
	aspectRatio = 16 / 9,
})
```

### `Reactily.createUICorner`

Creates a typed virtual `UICorner` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUICorner(props: uiCornerProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiCornerProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local corner = Reactily.createUICorner({
	cornerRadius = UDim.new(0, 10),
})
```

### `Reactily.createUIGradient`

Creates a typed virtual `UIGradient` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUIGradient(props: uiGradientProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiGradientProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local gradient = Reactily.createUIGradient({
	rotation = 90,
})
```

### `Reactily.createUIGridLayout`

Creates a typed virtual `UIGridLayout` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUIGridLayout(props: uiGridLayoutProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiGridLayoutProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local layout = Reactily.createUIGridLayout({
	cellSize = UDim2.fromOffset(120, 120),
	cellPadding = UDim2.fromOffset(8, 8),
})
```

### `Reactily.createUIListLayout`

Creates a typed virtual `UIListLayout` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUIListLayout(props: uiListLayoutProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiListLayoutProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local layout = Reactily.createUIListLayout({
	padding = UDim.new(0, 8),
	fillDirection = Enum.FillDirection.Vertical,
})
```

### `Reactily.createUIPadding`

Creates a typed virtual `UIPadding` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUIPadding(props: uiPaddingProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiPaddingProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local padding = Reactily.createUIPadding({
	paddingLeft = UDim.new(0, 12),
	paddingRight = UDim.new(0, 12),
})
```

### `Reactily.createUIPageLayout`

Creates a typed virtual `UIPageLayout` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUIPageLayout(props: uiPageLayoutProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiPageLayoutProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local layout = Reactily.createUIPageLayout({
	animated = true,
	circular = false,
})
```

### `Reactily.createUIScale`

Creates a typed virtual `UIScale` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUIScale(props: uiScaleProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiScaleProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local scale = Reactily.createUIScale({
	scale = 1.1,
})
```

### `Reactily.createUISizeConstraint`

Creates a typed virtual `UISizeConstraint` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUISizeConstraint(props: uiSizeConstraintProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiSizeConstraintProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local constraint = Reactily.createUISizeConstraint({
	minSize = Vector2.new(200, 100),
	maxSize = Vector2.new(800, 600),
})
```

### `Reactily.createUIStroke`

Creates a typed virtual `UIStroke` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUIStroke(props: uiStrokeProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiStrokeProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local stroke = Reactily.createUIStroke({
	thickness = 2,
	transparency = .25,
})
```

### `Reactily.createUITextSizeConstraint`

Creates a typed virtual `UITextSizeConstraint` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createUITextSizeConstraint(props: uiTextSizeConstraintProps?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `uiTextSizeConstraintProps?` | No | Typed property table for this Roblox host class. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local constraint = Reactily.createUITextSizeConstraint({
	minTextSize = 14,
	maxTextSize = 32,
})
```

### `Reactily.createVideoFrame`

Creates a typed virtual `VideoFrame` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createVideoFrame(props: videoFrameProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `videoFrameProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createVideoFrame({
	size = UDim2.fromOffset(640, 360),
	video = "rbxassetid://123456789",
})
```

### `Reactily.createViewportFrame`

Creates a typed virtual `ViewportFrame` element with class-specific prop autocomplete.

#### Signature

```lua
Reactily.createViewportFrame(props: viewportFrameProps?, children: {element}?): element
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `props` | `viewportFrameProps?` | No | Typed property table for this Roblox host class. |
| `children` | `{element}?` | No | Optional child Reactily elements rendered beneath this element/component. |

#### Returns

A virtual `Reactily.element`.

#### Usage

```lua
local element = Reactily.createViewportFrame({
	size = UDim2.fromOffset(500, 300),
	currentCamera = camera,
})
```

### `Reactily.distinctSignal`

Creates a derived signal that suppresses consecutive duplicate values.

#### Signature

```lua
Reactily.distinctSignal<T>(source: signal<T>): signal<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `signal<T>` | Yes | Source Reactily atom, binding, or signal. |

#### Returns

A `signal<T>`.

#### Usage

```lua
local unique = Reactily.distinctSignal(source)
```

### `Reactily.filterSignal`

Creates a derived signal that forwards only values accepted by `predicate`.

#### Signature

```lua
Reactily.filterSignal<T>(source: signal<T>, predicate: (value: T) -> boolean): signal<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `signal<T>` | Yes | Source Reactily atom, binding, or signal. |
| `predicate` | `(value: T) -> boolean` | Yes | Function returning `true` when a signal value should be forwarded. |

#### Returns

A `signal<T>`.

#### Usage

```lua
local even = Reactily.filterSignal(source, function(value)
	return value % 2 == 0
end)
```

### `Reactily.formatBinding`

Creates a derived string binding using a formatter.

#### Signature

```lua
Reactily.formatBinding<T>(source: binding<T>, formatter: (value: T) -> string): binding<string>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `binding<T>` | Yes | Source Reactily atom, binding, or signal. |
| `formatter` | `(value: T) -> string` | Yes | Function that converts the source value into a display string. |

#### Returns

A `binding<string>`.

#### Usage

```lua
local text = Reactily.formatBinding(intensity, function(value)
	return `{math.round(value * 100)}%`
end)
```

### `Reactily.getVersion`

Returns the current Reactily package version.

#### Signature

```lua
Reactily.getVersion(): string
```

#### Parameters

_No parameters._

#### Returns

A string.

#### Usage

```lua
local version = Reactily.getVersion()
```

### `Reactily.mapBinding`

Creates a derived binding by transforming the source value.

#### Signature

```lua
Reactily.mapBinding<A, B>(source: binding<A>, mapper: (value: A) -> B): binding<B>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `binding<A>` | Yes | Source Reactily atom, binding, or signal. |
| `mapper` | `(value: A) -> B` | Yes | Function that transforms one or more source values into the derived value. |

#### Returns

A `binding<B>`.

#### Usage

```lua
local percent = Reactily.mapBinding(intensity, function(value)
	return value * 100
end)
```

### `Reactily.mapSignal`

Creates a derived signal by transforming every emitted source value.

#### Signature

```lua
Reactily.mapSignal<A, B>(source: signal<A>, mapper: (value: A) -> B): signal<B>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `signal<A>` | Yes | Source Reactily atom, binding, or signal. |
| `mapper` | `(value: A) -> B` | Yes | Function that transforms one or more source values into the derived value. |

#### Returns

A `signal<B>`.

#### Usage

```lua
local labels = Reactily.mapSignal(source, function(value)
	return `Fixture {value}`
end)
```

### `Reactily.mergeSignals`

Creates a derived signal that forwards emissions from all supplied sources.

#### Signature

```lua
Reactily.mergeSignals<T>(sources: {signal<T>}): signal<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `sources` | `{signal<T>}` | Yes | Source signals to merge into one derived signal. |

#### Returns

A `signal<T>`.

#### Usage

```lua
local merged = Reactily.mergeSignals({
	firstSignal,
	secondSignal,
})
```

### `Reactily.new`

Alias of `Reactily.createRoot(parent)`.

#### Signature

```lua
Reactily.new(parent: Instance): root
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `parent` | `Instance` | Yes | Roblox Instance that receives the root's rendered host tree. |

#### Returns

A Reactily render root.

#### Usage

```lua
local root = Reactily.new(playerGui)
```

### `Reactily.playTween`

Creates and immediately plays an owned TweenService animation.

#### Signature

```lua
Reactily.playTween(
	instance: Instance,
	goals: {[string]: any},
	options: tweenOptions
): animation
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `instance` | `Instance` | Yes | Roblox Instance used by the requested Reactily helper. |
| `goals` | `{[string]: any}` | Yes | Roblox TweenService goal property table. |
| `options` | `tweenOptions` | Yes | Typed Tween configuration. |

#### Returns

An owned Reactily animation wrapper.

#### Usage

```lua
local animation = Reactily.playTween(frame, {
	BackgroundTransparency = 0,
}, {
	time = .2,
})
```

### `Reactily.resolveTheme`

Immediately derives a value from the theme's current tokens.

#### Signature

```lua
Reactily.resolveTheme<T, R>(themeValue: theme<T>, selectorFunction: (tokens: T) -> R): R
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `themeValue` | `theme<T>` | Yes | Reactily theme whose current token value is read. |
| `selectorFunction` | `(tokens: T) -> R` | Yes | Function that derives a selected/computed value from the source. |

#### Returns

`R`.

#### Usage

```lua
local accent = Reactily.resolveTheme(theme, function(tokens)
	return tokens.accent
end)
```

### `Reactily.resolveVirtualList`

Calculates the visible fixed-size list range plus overscan.

#### Signature

```lua
Reactily.resolveVirtualList(
	itemCount: number,
	itemSize: number,
	scrollOffset: number,
	viewportSize: number,
	overscan: number?
): virtualRange
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `itemCount` | `number` | Yes | Total number of logical items in the virtualized list. |
| `itemSize` | `number` | Yes | Fixed pixel size of one virtual-list item. Must be greater than zero. |
| `scrollOffset` | `number` | Yes | Current scroll position in pixels. |
| `viewportSize` | `number` | Yes | Visible viewport size in pixels. |
| `overscan` | `number?` | No | Optional number of extra virtual-list rows rendered before and after the visible range. |

#### Returns

A virtual-list range containing `first`, `last`, `offset`, and `totalSize`.

#### Usage

```lua
local range = Reactily.resolveVirtualList(
	5000,
	44,
	scrollingFrame.CanvasPosition.Y,
	scrollingFrame.AbsoluteWindowSize.Y,
	3
)
```

### `Reactily.roundBinding`

Creates a derived numeric binding rounded to the requested decimal precision.

#### Signature

```lua
Reactily.roundBinding(source: binding<number>, precision: number): binding<number>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `binding<number>` | Yes | Source Reactily atom, binding, or signal. |
| `precision` | `number` | Yes | Number of decimal places retained by numeric rounding. |

#### Returns

A `binding<number>`.

#### Usage

```lua
local rounded = Reactily.roundBinding(valueBinding, 2)
```

### `Reactily.skipSignal`

Creates a derived signal that ignores the first `amount` source emissions.

#### Signature

```lua
Reactily.skipSignal<T>(source: signal<T>, amount: number): signal<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `signal<T>` | Yes | Source Reactily atom, binding, or signal. |
| `amount` | `number` | Yes | Number of source emissions to skip, decrement by, or otherwise apply as the requested amount. |

#### Returns

A `signal<T>`.

#### Usage

```lua
local afterWarmup = Reactily.skipSignal(source, 2)
```

### `Reactily.sliceVirtualList`

Returns the source-array entries covered by a virtual range.

#### Signature

```lua
Reactily.sliceVirtualList<T>(items: {T}, rangeValue: virtualRange): {T}
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `items` | `{T}` | Yes | Source array to slice using the virtual range. |
| `rangeValue` | `virtualRange` | Yes | Virtualized range returned by `Reactily.resolveVirtualList()`. |

#### Returns

`{T}`.

#### Usage

```lua
local visibleItems = Reactily.sliceVirtualList(items, range)
```

### `Reactily.takeSignal`

Creates a derived signal that forwards at most `maximum` source emissions.

#### Signature

```lua
Reactily.takeSignal<T>(source: signal<T>, maximum: number): signal<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `source` | `signal<T>` | Yes | Source Reactily atom, binding, or signal. |
| `maximum` | `number` | Yes | Maximum allowed value or maximum number of signal emissions to forward. |

#### Returns

A `signal<T>`.

#### Usage

```lua
local firstFive = Reactily.takeSignal(source, 5)
```

### `Reactily.useAttribute`

Uses component state synchronized with a Roblox Attribute.

#### Signature

```lua
Reactily.useAttribute<T>(
	instance: Instance,
	attributeName: string,
	defaultValue: T
): (T, (value: T) -> ())
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `instance` | `Instance` | Yes | Roblox Instance used by the requested Reactily helper. |
| `attributeName` | `string` | Yes | Roblox Attribute name owned or observed by this Reactily state helper. |
| `defaultValue` | `T` | Yes | Fallback value used when the Roblox Attribute currently has no value. |

#### Returns

`(T, (value: T) -> ())`.

#### Usage

```lua
local enabled, setEnabled = Reactily.useAttribute(
	fixture,
	"enabled",
	true
)
```

### `Reactily.useBoolean`

Provides boolean state plus stable enable, disable, and toggle functions.

#### Signature

```lua
Reactily.useBoolean(initialValue: boolean?): (boolean, () -> (), () -> (), () -> ())
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `boolean?` | No | Initial typed value. |

#### Returns

`(boolean, () -> (), () -> (), () -> ())`.

#### Usage

```lua
local enabled, enable, disable, toggle = Reactily.useBoolean(false)
```

### `Reactily.useCallback`

Memoizes a callback/value by dependency array.

#### Signature

```lua
Reactily.useCallback<T>(callback: T, dependencies: {any}?): T
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `T` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |
| `dependencies` | `{any}?` | No | Dependency array used to decide whether the memo, callback, or effect should update. `nil` means it is treated as changed every render. |

#### Returns

`T`.

#### Usage

```lua
local onClick = Reactily.useCallback(function()
	print(selection)
end, {selection})
```

### `Reactily.useCounter`

Provides numeric state plus increment/decrement/reset/set controls.

#### Signature

```lua
Reactily.useCounter(initialValue: number?): (number, counterControls)
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `number?` | No | Initial typed value. |

#### Returns

`(number, counterControls)`.

#### Usage

```lua
local count, controls = Reactily.useCounter(0)
controls.increment()
```

### `Reactily.useDebouncedValue`

Returns a value that updates after the requested one-shot delay.

#### Signature

```lua
Reactily.useDebouncedValue<T>(value: T, delaySeconds: number): T
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `T` | Yes | Typed value passed to the hook/helper. |
| `delaySeconds` | `number` | Yes | One-shot debounce delay in seconds. Must be non-negative. |

#### Returns

`T`.

#### Usage

```lua
local debouncedQuery = Reactily.useDebouncedValue(query, .2)
```

### `Reactily.useEffect`

Runs an effect after a completed component render and supports cleanup.

#### Signature

```lua
Reactily.useEffect(callback: () -> (() -> ())?, dependencies: {any}?)
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `() -> (() -> ())?, dependencies: {any}?` | No | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

#### Returns

No value.

#### Usage

```lua
Reactily.useEffect(function()
	local connection = signal:Connect(onChanged)

	return function()
		connection:Disconnect()
	end
end, {signal})
```

### `Reactily.useMemo`

Memoizes a calculated value by dependency array.

#### Signature

```lua
Reactily.useMemo<T>(factory: () -> T, dependencies: {any}?): T
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `factory` | `() -> T, dependencies: {any}?` | No | Function that calculates and returns the memoized value. |

#### Returns

`T`.

#### Usage

```lua
local expensive = Reactily.useMemo(function()
	return calculate(data)
end, {data})
```

### `Reactily.usePrevious`

Returns the value from the previous completed render, or `nil` initially.

#### Signature

```lua
Reactily.usePrevious<T>(value: T): T?
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `T` | Yes | Typed value passed to the hook/helper. |

#### Returns

`T?`.

#### Usage

```lua
local previous = Reactily.usePrevious(current)
```

### `Reactily.useReducer`

Provides typed reducer-driven component state and a stable dispatch function.

#### Signature

```lua
Reactily.useReducer<S, A>(
	reducer: (stateValue: S, action: A) -> S,
	initialState: S
): (S, reducerDispatch<A>)
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `reducer` | `(stateValue: S, action: A) -> S,
	initialState: S` | Yes | Pure reducer function that resolves the next state from the current state and action. |

#### Returns

`(S, reducerDispatch<A>)`.

#### Usage

```lua
local state, dispatch = Reactily.useReducer(reducer, initialState)
dispatch({type = "increment"})
```

### `Reactily.useRef`

Creates persistent mutable component storage that does not trigger rerenders.

#### Signature

```lua
Reactily.useRef<T>(initialValue: T): ref<T>
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `T` | Yes | Initial typed value. |

#### Returns

`ref<T>`.

#### Usage

```lua
local dragging = Reactily.useRef(false)
dragging.current = true
```

### `Reactily.useState`

Creates typed component state and a stable setter.

#### Signature

```lua
Reactily.useState<T>(initialValue: T): (T, stateSetter<T>)
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `T` | Yes | Initial typed value. |

#### Returns

`(T, stateSetter<T>)`.

#### Usage

```lua
local count, setCount = Reactily.useState(0)
setCount(1)
```

### `Reactily.useToggle`

Provides boolean state, a toggle function, and an explicit setter.

#### Signature

```lua
Reactily.useToggle(initialValue: boolean?): (boolean, () -> (), (value: boolean) -> ())
```

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `initialValue` | `boolean?` | No | Initial typed value. |

#### Returns

`(boolean, () -> (), (value: boolean) -> ())`.

#### Usage

```lua
local open, toggle, setOpen = Reactily.useToggle(false)
toggle()
setOpen(true)
```

## Returned Object APIs

### `root.*`

#### `root.render`

Renders/reconciles the requested element tree. Pass `nil` to unmount the current tree while keeping the root.

**Signature**

```lua
root.render(elementValue: Reactily.element?) -> ()
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `elementValue` | `Reactily.element?` | No | Value supplied to `elementValue`. |

**Returns**

`()`.

**Usage**

```lua
root.render(appElement)
```

#### `root.flush`

Immediately flushes work currently queued in the root scheduler.

**Signature**

```lua
root.flush() -> ()
```

**Parameters**

_No parameters._

**Returns**

`()`.

**Usage**

```lua
root.flush()
```

#### `root.batch`

Batches render requests and applies the final pending render when the outermost batch ends.

**Signature**

```lua
root.batch(callback: () -> ()) -> ()
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `() -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`()`.

**Usage**

```lua
root.batch(function()
	root.render(firstTree)
	root.render(finalTree)
end)
```

#### `root.suspend`

Suspends rendering. Returns `false` if already suspended.

**Signature**

```lua
root.suspend() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
local changed = root.suspend()
```

#### `root.resume`

Resumes rendering and applies pending work. Returns `false` if already active.

**Signature**

```lua
root.resume() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
local changed = root.resume()
```

#### `root.isSuspended`

Reports whether this root is currently suspended.

**Signature**

```lua
root.isSuspended() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
if root.isSuspended() then
	print("suspended")
end
```

#### `root.getElement`

Returns the root's currently requested element.

**Signature**

```lua
root.getElement() -> Reactily.element?
```

**Parameters**

_No parameters._

**Returns**

`Reactily.element?`.

**Usage**

```lua
local element = root.getElement()
```

#### `root.getParent`

Returns the Roblox parent owned by this root.

**Signature**

```lua
root.getParent() -> Instance
```

**Parameters**

_No parameters._

**Returns**

`Instance`.

**Usage**

```lua
local parent = root.getParent()
```

#### `root.isDeleted`

Reports whether this root has been deleted.

**Signature**

```lua
root.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
if root.isDeleted() then return end
```

#### `root.delete`

Deletes the rendered tree, scheduler, hooks, connections, and other root-owned runtime.

**Signature**

```lua
root.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
root.delete()
```

### `atom.*`

#### `atom.get`

Returns the current atom value.

**Signature**

```lua
atom.get() -> T
```

**Parameters**

_No parameters._

**Returns**

`T`.

**Usage**

```lua
local value = atom.get()
```

#### `atom.set`

Sets the atom if the value changed. Returns whether a change occurred.

**Signature**

```lua
atom.set(value: T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `T` | Yes | Typed value passed to the hook/helper. |

**Returns**

`boolean`.

**Usage**

```lua
atom.set(10)
```

#### `atom.update`

Calculates and sets the next atom value.

**Signature**

```lua
atom.update(updater: (previous: T) -> T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `updater` | `(previous: T) -> T` | Yes | Value supplied to `updater`. |

**Returns**

`boolean`.

**Usage**

```lua
atom.update(function(previous)
	return previous + 1
end)
```

#### `atom.subscribe`

Subscribes to meaningful atom changes.

**Signature**

```lua
atom.subscribe(callback: (change: Reactily.atomChange<T>) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(change: Reactily.atomChange<T>) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
local connection = atom.subscribe(function(change)
	print(change.current)
end)
```

#### `atom.isDeleted`

Reports whether this atom is deleted.

**Signature**

```lua
atom.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(atom.isDeleted())
```

#### `atom.delete`

Deletes the atom's signal and any owned synchronization.

**Signature**

```lua
atom.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
atom.delete()
```

### `computed.*`

#### `computed.get`

Returns the current computed value.

**Signature**

```lua
computed.get() -> T
```

**Parameters**

_No parameters._

**Returns**

`T`.

**Usage**

```lua
local value = computed.get()
```

#### `computed.subscribe`

Subscribes to computed-value changes.

**Signature**

```lua
computed.subscribe(callback: (change: Reactily.atomChange<T>) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(change: Reactily.atomChange<T>) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
computed.subscribe(function(change)
	print(change.current)
end)
```

#### `computed.isDeleted`

Reports whether the computed state is deleted.

**Signature**

```lua
computed.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(computed.isDeleted())
```

#### `computed.delete`

Deletes the computed state and disconnects its source subscription.

**Signature**

```lua
computed.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
computed.delete()
```

### `historyAtom.*`

#### `historyAtom.get`

Returns the current history value.

**Signature**

```lua
historyAtom.get() -> T
```

**Parameters**

_No parameters._

**Returns**

`T`.

**Usage**

```lua
local value = historyAtom.get()
```

#### `historyAtom.set`

Sets a new current value and records the previous value in undo history.

**Signature**

```lua
historyAtom.set(value: T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `T` | Yes | Typed value passed to the hook/helper. |

**Returns**

`boolean`.

**Usage**

```lua
historyAtom.set(nextPosition)
```

#### `historyAtom.update`

Updates current state while recording history.

**Signature**

```lua
historyAtom.update(updater: (previous: T) -> T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `updater` | `(previous: T) -> T` | Yes | Value supplied to `updater`. |

**Returns**

`boolean`.

**Usage**

```lua
historyAtom.update(updatePosition)
```

#### `historyAtom.subscribe`

Subscribes to history-state changes.

**Signature**

```lua
historyAtom.subscribe(callback: (change: Reactily.atomChange<T>) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(change: Reactily.atomChange<T>) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
historyAtom.subscribe(onPositionChanged)
```

#### `historyAtom.canUndo`

Reports whether an undo entry exists.

**Signature**

```lua
historyAtom.canUndo() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
if historyAtom.canUndo() then
	historyAtom.undo()
end
```

#### `historyAtom.canRedo`

Reports whether a redo entry exists.

**Signature**

```lua
historyAtom.canRedo() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
if historyAtom.canRedo() then
	historyAtom.redo()
end
```

#### `historyAtom.undo`

Moves to the previous value when available.

**Signature**

```lua
historyAtom.undo() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
historyAtom.undo()
```

#### `historyAtom.redo`

Moves to the next redo value when available.

**Signature**

```lua
historyAtom.redo() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
historyAtom.redo()
```

#### `historyAtom.clearHistory`

Clears undo and redo stacks without changing the current value.

**Signature**

```lua
historyAtom.clearHistory() -> ()
```

**Parameters**

_No parameters._

**Returns**

`()`.

**Usage**

```lua
historyAtom.clearHistory()
```

#### `historyAtom.getPastCount`

Returns retained undo-entry count.

**Signature**

```lua
historyAtom.getPastCount() -> number
```

**Parameters**

_No parameters._

**Returns**

`number`.

**Usage**

```lua
local count = historyAtom.getPastCount()
```

#### `historyAtom.getFutureCount`

Returns retained redo-entry count.

**Signature**

```lua
historyAtom.getFutureCount() -> number
```

**Parameters**

_No parameters._

**Returns**

`number`.

**Usage**

```lua
local count = historyAtom.getFutureCount()
```

#### `historyAtom.isDeleted`

Reports whether this history atom is deleted.

**Signature**

```lua
historyAtom.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(historyAtom.isDeleted())
```

#### `historyAtom.delete`

Deletes current state and clears history.

**Signature**

```lua
historyAtom.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
historyAtom.delete()
```

### `store.*`

#### `store.get`

Returns current store state.

**Signature**

```lua
store.get() -> T
```

**Parameters**

_No parameters._

**Returns**

`T`.

**Usage**

```lua
local state = store.get()
```

#### `store.set`

Replaces store state only when the reference/value changed.

**Signature**

```lua
store.set(state: T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `state` | `T` | Yes | Value supplied to `state`. |

**Returns**

`boolean`.

**Usage**

```lua
store.set(nextState)
```

#### `store.update`

Calculates and applies the next store state.

**Signature**

```lua
store.update(updater: (state: T) -> T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `updater` | `(state: T) -> T` | Yes | Value supplied to `updater`. |

**Returns**

`boolean`.

**Usage**

```lua
store.update(function(previous)
	return nextState
end)
```

#### `store.reset`

Restores the initial store state.

**Signature**

```lua
store.reset() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
store.reset()
```

#### `store.subscribe`

Subscribes to meaningful whole-store changes.

**Signature**

```lua
store.subscribe(callback: (change) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(change) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
store.subscribe(function(change)
	print(change.current)
end)
```

#### `store.select`

Creates a derived selector that emits only when its selected value changes.

**Signature**

```lua
store.select<R>(selectorFunction: (state: T) -> R) -> Reactily.selector<R>
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `selectorFunction` | `(state: T) -> R` | Yes | Function that derives a selected/computed value from the source. |

**Returns**

`Reactily.selector<R>`.

**Usage**

```lua
local page = store.select(function(state)
	return state.page
end)
```

#### `store.batch`

Groups nested store updates into one final notification.

**Signature**

```lua
store.batch(callback: () -> ()) -> ()
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `() -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`()`.

**Usage**

```lua
store.batch(function()
	store.set(first)
	store.set(final)
end)
```

#### `store.isDeleted`

Reports whether the store is deleted.

**Signature**

```lua
store.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(store.isDeleted())
```

#### `store.delete`

Deletes subscriptions and all active selectors owned by the store.

**Signature**

```lua
store.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
store.delete()
```

### `selector.*`

#### `selector.get`

Returns the current selected value.

**Signature**

```lua
selector.get() -> T
```

**Parameters**

_No parameters._

**Returns**

`T`.

**Usage**

```lua
local value = selector.get()
```

#### `selector.subscribe`

Subscribes to meaningful selected-value changes.

**Signature**

```lua
selector.subscribe(callback: (change) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(change) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
selector.subscribe(onSelectedChanged)
```

#### `selector.isDeleted`

Reports whether this selector is deleted.

**Signature**

```lua
selector.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(selector.isDeleted())
```

#### `selector.delete`

Disconnects the selector from its source store.

**Signature**

```lua
selector.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
selector.delete()
```

### `binding.*`

#### `binding.get`

Returns the current binding value.

**Signature**

```lua
binding.get() -> T
```

**Parameters**

_No parameters._

**Returns**

`T`.

**Usage**

```lua
local value = binding.get()
```

#### `binding.set`

Sets the binding only when changed.

**Signature**

```lua
binding.set(value: T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `T` | Yes | Typed value passed to the hook/helper. |

**Returns**

`boolean`.

**Usage**

```lua
binding.set(.5)
```

#### `binding.subscribe`

Subscribes to binding changes.

**Signature**

```lua
binding.subscribe(callback: (change: Reactily.bindingChange<T>) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(change: Reactily.bindingChange<T>) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
binding.subscribe(onChanged)
```

#### `binding.isDeleted`

Reports whether the binding is deleted.

**Signature**

```lua
binding.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(binding.isDeleted())
```

#### `binding.delete`

Deletes this binding and disconnects any upstream subscriptions owned by derived bindings.

**Signature**

```lua
binding.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
binding.delete()
```

### `signal.*`

#### `signal.connect`

Adds a persistent listener.

**Signature**

```lua
signal.connect(callback: (value: T) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(value: T) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
local connection = signal.connect(onValue)
```

#### `signal.once`

Adds a listener that disconnects after its first emission.

**Signature**

```lua
signal.once(callback: (value: T) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(value: T) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
signal.once(onFirstValue)
```

#### `signal.fire`

Emits one value to current listeners.

**Signature**

```lua
signal.fire(value: T) -> ()
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `T` | Yes | Typed value passed to the hook/helper. |

**Returns**

`()`.

**Usage**

```lua
signal.fire(5)
```

#### `signal.getListenerCount`

Returns current listener count.

**Signature**

```lua
signal.getListenerCount() -> number
```

**Parameters**

_No parameters._

**Returns**

`number`.

**Usage**

```lua
print(signal.getListenerCount())
```

#### `signal.isDeleted`

Reports whether this signal is deleted.

**Signature**

```lua
signal.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(signal.isDeleted())
```

#### `signal.delete`

Deletes listeners and any upstream subscriptions owned by a derived signal.

**Signature**

```lua
signal.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
signal.delete()
```

### `connection.*`

#### `connection.disconnect`

Disconnects the Reactily signal listener. Returns whether it changed from connected to disconnected.

**Signature**

```lua
connection.disconnect() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
connection.disconnect()
```

### `scheduler.*`

#### `scheduler.enqueue`

Queues one callback and wakes the temporary scheduler Heartbeat.

**Signature**

```lua
scheduler.enqueue(callback: () -> ()) -> number
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `() -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`number`.

**Usage**

```lua
local taskId = scheduler.enqueue(runTask)
```

#### `scheduler.enqueueKeyed`

Queues keyed work or replaces the pending callback for the same key.

**Signature**

```lua
scheduler.enqueueKeyed(key: string, callback: () -> ()) -> number
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `key` | `string` | Yes | Optional stable identity key used by reconciliation. |
| `callback` | `() -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`number`.

**Usage**

```lua
scheduler.enqueueKeyed("render", renderNow)
```

#### `scheduler.cancel`

Cancels one pending task by id.

**Signature**

```lua
scheduler.cancel(taskId: number) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `taskId` | `number` | Yes | Value supplied to `taskId`. |

**Returns**

`boolean`.

**Usage**

```lua
scheduler.cancel(taskId)
```

#### `scheduler.cancelKey`

Cancels pending keyed work.

**Signature**

```lua
scheduler.cancelKey(key: string) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `key` | `string` | Yes | Optional stable identity key used by reconciliation. |

**Returns**

`boolean`.

**Usage**

```lua
scheduler.cancelKey("render")
```

#### `scheduler.isPending`

Reports whether keyed work is currently queued.

**Signature**

```lua
scheduler.isPending(key: string) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `key` | `string` | Yes | Optional stable identity key used by reconciliation. |

**Returns**

`boolean`.

**Usage**

```lua
if scheduler.isPending("render") then return end
```

#### `scheduler.getPendingCount`

Returns queued task count.

**Signature**

```lua
scheduler.getPendingCount() -> number
```

**Parameters**

_No parameters._

**Returns**

`number`.

**Usage**

```lua
print(scheduler.getPendingCount())
```

#### `scheduler.flush`

Immediately executes current pending tasks.

**Signature**

```lua
scheduler.flush() -> ()
```

**Parameters**

_No parameters._

**Returns**

`()`.

**Usage**

```lua
scheduler.flush()
```

#### `scheduler.clear`

Cancels all queued work and returns the scheduler to idle.

**Signature**

```lua
scheduler.clear() -> ()
```

**Parameters**

_No parameters._

**Returns**

`()`.

**Usage**

```lua
scheduler.clear()
```

#### `scheduler.isDeleted`

Reports whether the scheduler is deleted.

**Signature**

```lua
scheduler.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(scheduler.isDeleted())
```

#### `scheduler.delete`

Deletes queued state and disconnects scheduler runtime.

**Signature**

```lua
scheduler.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
scheduler.delete()
```

### `objectPool.*`

#### `objectPool.acquire`

Returns a reusable object or creates one when none are available.

**Signature**

```lua
objectPool.acquire() -> T
```

**Parameters**

_No parameters._

**Returns**

`T`.

**Usage**

```lua
local object = objectPool.acquire()
```

#### `objectPool.release`

Resets and returns an object to the pool, or final-deletes it if the pool is full.

**Signature**

```lua
objectPool.release(object: T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `object` | `T` | Yes | Value supplied to `object`. |

**Returns**

`boolean`.

**Usage**

```lua
objectPool.release(object)
```

#### `objectPool.clear`

Final-deletes all currently available pooled objects.

**Signature**

```lua
objectPool.clear() -> ()
```

**Parameters**

_No parameters._

**Returns**

`()`.

**Usage**

```lua
objectPool.clear()
```

#### `objectPool.getAvailableCount`

Returns count of objects ready for reuse.

**Signature**

```lua
objectPool.getAvailableCount() -> number
```

**Parameters**

_No parameters._

**Returns**

`number`.

**Usage**

```lua
print(objectPool.getAvailableCount())
```

#### `objectPool.getCreatedCount`

Returns count of objects currently owned/created by the pool.

**Signature**

```lua
objectPool.getCreatedCount() -> number
```

**Parameters**

_No parameters._

**Returns**

`number`.

**Usage**

```lua
print(objectPool.getCreatedCount())
```

#### `objectPool.isDeleted`

Reports whether the pool is deleted.

**Signature**

```lua
objectPool.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(objectPool.isDeleted())
```

#### `objectPool.delete`

Clears reusable objects and permanently closes the pool.

**Signature**

```lua
objectPool.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
objectPool.delete()
```

### `theme.*`

#### `theme.get`

Returns current theme tokens.

**Signature**

```lua
theme.get() -> T
```

**Parameters**

_No parameters._

**Returns**

`T`.

**Usage**

```lua
local tokens = theme.get()
```

#### `theme.set`

Replaces theme tokens when changed.

**Signature**

```lua
theme.set(value: T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `value` | `T` | Yes | Typed value passed to the hook/helper. |

**Returns**

`boolean`.

**Usage**

```lua
theme.set(nextTokens)
```

#### `theme.update`

Calculates and applies new tokens.

**Signature**

```lua
theme.update(updater: (value: T) -> T) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `updater` | `(value: T) -> T` | Yes | Value supplied to `updater`. |

**Returns**

`boolean`.

**Usage**

```lua
theme.update(updateTokens)
```

#### `theme.subscribe`

Subscribes to theme-token changes.

**Signature**

```lua
theme.subscribe(callback: (value: T) -> ()) -> Reactily.connection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(value: T) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`Reactily.connection`.

**Usage**

```lua
theme.subscribe(onThemeChanged)
```

#### `theme.isDeleted`

Reports whether the theme is deleted.

**Signature**

```lua
theme.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(theme.isDeleted())
```

#### `theme.delete`

Deletes the theme signal and listeners.

**Signature**

```lua
theme.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
theme.delete()
```

### `focusGroup.*`

#### `focusGroup.add`

Adds a GUI object if it is not already registered.

**Signature**

```lua
focusGroup.add(object: GuiObject) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `object` | `GuiObject` | Yes | Value supplied to `object`. |

**Returns**

`boolean`.

**Usage**

```lua
focusGroup.add(playButton)
```

#### `focusGroup.remove`

Removes a registered GUI object.

**Signature**

```lua
focusGroup.remove(object: GuiObject) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `object` | `GuiObject` | Yes | Value supplied to `object`. |

**Returns**

`boolean`.

**Usage**

```lua
focusGroup.remove(playButton)
```

#### `focusGroup.clear`

Clears registered focus items.

**Signature**

```lua
focusGroup.clear() -> ()
```

**Parameters**

_No parameters._

**Returns**

`()`.

**Usage**

```lua
focusGroup.clear()
```

#### `focusGroup.focusFirst`

Focuses the first valid visible/selectable registered object.

**Signature**

```lua
focusGroup.focusFirst() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
focusGroup.focusFirst()
```

#### `focusGroup.focusLast`

Focuses the last valid visible/selectable registered object.

**Signature**

```lua
focusGroup.focusLast() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
focusGroup.focusLast()
```

#### `focusGroup.getItems`

Returns a cloned list of registered items.

**Signature**

```lua
focusGroup.getItems() -> {GuiObject}
```

**Parameters**

_No parameters._

**Returns**

`{GuiObject}`.

**Usage**

```lua
local items = focusGroup.getItems()
```

#### `focusGroup.isDeleted`

Reports whether this focus group is deleted.

**Signature**

```lua
focusGroup.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(focusGroup.isDeleted())
```

#### `focusGroup.delete`

Clears the group and prevents further use.

**Signature**

```lua
focusGroup.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
focusGroup.delete()
```

### `animation.*`

#### `animation.play`

Starts the owned Tween.

**Signature**

```lua
animation.play() -> ()
```

**Parameters**

_No parameters._

**Returns**

`()`.

**Usage**

```lua
animation.play()
```

#### `animation.cancel`

Cancels the Tween if the animation is still active.

**Signature**

```lua
animation.cancel() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
animation.cancel()
```

#### `animation.onCompleted`

Connects a Reactily-owned Tween completion callback.

**Signature**

```lua
animation.onCompleted(callback: (playbackState: Enum.PlaybackState) -> ()) -> RBXScriptConnection
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `callback` | `(playbackState: Enum.PlaybackState) -> ()` | Yes | Function Reactily calls for the operation, subscription, effect, batch, scheduled task, or event. |

**Returns**

`RBXScriptConnection`.

**Usage**

```lua
animation.onCompleted(function(playbackState)
	print(playbackState)
end)
```

#### `animation.isDeleted`

Reports whether this animation owner is deleted.

**Signature**

```lua
animation.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(animation.isDeleted())
```

#### `animation.delete`

Disconnects completion listeners, cancels the Tween, and destroys the Roblox Tween.

**Signature**

```lua
animation.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
animation.delete()
```

### `diagnostics.*`

#### `diagnostics.increment`

Adds to a named counter and returns the new value.

**Signature**

```lua
diagnostics.increment(name: string, amount: number?) -> number
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `name` | `string` | Yes | Value supplied to `name`. |
| `amount` | `number?` | No | Number of source emissions to skip, decrement by, or otherwise apply as the requested amount. |

**Returns**

`number`.

**Usage**

```lua
diagnostics.increment("renders")
```

#### `diagnostics.get`

Returns one counter or `0` when absent.

**Signature**

```lua
diagnostics.get(name: string) -> number
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `name` | `string` | Yes | Value supplied to `name`. |

**Returns**

`number`.

**Usage**

```lua
local renders = diagnostics.get("renders")
```

#### `diagnostics.reset`

Removes one counter. Returns whether it existed.

**Signature**

```lua
diagnostics.reset(name: string) -> boolean
```

**Parameters**

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `name` | `string` | Yes | Value supplied to `name`. |

**Returns**

`boolean`.

**Usage**

```lua
diagnostics.reset("renders")
```

#### `diagnostics.resetAll`

Clears every counter.

**Signature**

```lua
diagnostics.resetAll() -> ()
```

**Parameters**

_No parameters._

**Returns**

`()`.

**Usage**

```lua
diagnostics.resetAll()
```

#### `diagnostics.snapshot`

Returns a cloned counter table.

**Signature**

```lua
diagnostics.snapshot() -> {[string]: number}
```

**Parameters**

_No parameters._

**Returns**

`{[string]: number}`.

**Usage**

```lua
local snapshot = diagnostics.snapshot()
```

#### `diagnostics.isDeleted`

Reports whether diagnostics are deleted.

**Signature**

```lua
diagnostics.isDeleted() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
print(diagnostics.isDeleted())
```

#### `diagnostics.delete`

Clears counters and permanently closes this diagnostics owner.

**Signature**

```lua
diagnostics.delete() -> boolean
```

**Parameters**

_No parameters._

**Returns**

`boolean`.

**Usage**

```lua
diagnostics.delete()
```

## Shared Argument Shapes

### `atomChange<T>` / `bindingChange<T>` / store/selector change

```lua
{
	current = nextValue,
	previous = previousValue,
}
```

These records are delivered only when the owning state system resolves a meaningful value change.

### `Reactily.tweenOptions`

```lua
{
	time: number,
	easingStyle: Enum.EasingStyle?,
	easingDirection: Enum.EasingDirection?,
	repeatCount: number?,
	reverses: boolean?,
	delayTime: number?,
}
```

`time` is required. The remaining fields use Reactily's TweenInfo defaults when omitted.

### Host creator `props`

Each typed creator receives its own class-specific props type. Common host metadata includes `key`, `ref`, `attributes`, and `tags`; GUI creators also expose relevant Roblox properties and supported `on...` event callbacks. See the earlier **Typed Prop Reference** for every field.

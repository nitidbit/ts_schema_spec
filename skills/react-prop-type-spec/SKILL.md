---
name: react-prop-type-spec
description: >
  Write or update RSpec tests that use TsSchemaSpec + match_schema to
  verify a Rails endpoint's payload matches the TypeScript types consumed by a
  React component. TRIGGER automatically (without being asked) whenever: adding
  a new controller action; changing serialization in an existing action (helper
  method, as_json fields, included associations); adding or renaming a key in a
  render json: response or in props passed to a React component; converting a
  Rails-mounted component from .jsx to .tsx; deleting a component's propTypes;
  or adding a mount site that renders an existing component from an action that
  has no match_schema spec yet. Applies to both JSON endpoints (render json:)
  and HTML actions that pass props via react_component. Invoked as
  /react-prop-type-spec.
---

When invoked, write or update the RSpec test(s) that confirm the controller
payload matches the TypeScript type(s) the React side expects. Follow every
step below in order.

## Why this exists, and when it is owed

TypeScript checks only our own call sites. Props arriving from Rails are `any`
at runtime, so nothing but this spec ever compares the two sides — and a
mismatch is silent: a missing key renders blank, a wrong type mis-renders,
neither raises.

The failure mode to keep in mind: Rails emits `level`, the component reads
`assignedEntity`, both sides have passing tests, both are green, and every
checkbox in the matrix silently renders disabled. Neither side is wrong on its
own, which is why neither side's tests notice.

So this is a **coverage rule, not only a change-triggered one**. The spec is
owed whenever the Rails-renders-React pairing exists, which includes cases with
no Ruby-side diff at all:

- a component is converted `.jsx` → `.tsx`, or its `propTypes` are deleted;
- a new mount site renders an already-typed component from a different action;
- serialization changes, a prop is added or renamed, or a new action is added.

Two scoping rules keep this from multiplying:

- **One spec per action, not per mount site.** A partial that mounts the same
  component five times in one action is one spec.
- **Assert on the component Rails actually mounts.** A child that only receives
  props from its parent is covered transitively — register the parent's props
  type, not the child's.

## Step 0 — Is this call site already covered?

Covered = the spec for **the action rendering it** has a `match_schema` example
asserting `react_component_props("ThatComponent")`. Find the action, grep its
spec for `match_schema`, and check each hit is the same component _and_ the
same action — a sibling component, another action, or a source file with no
example is not coverage. Covered → stop. Otherwise continue.

## Step 1 — Identify the endpoint and its TypeScript consumer

Read the controller action being added or changed. Find the React component
that consumes it (if no React component consumes the data, exit the skill):

- For **JSON actions** (`render json:`): find the `fetch`/`axios` call and the
  TypeScript type it parses into.
- For **HTML actions** (props passed via `react_component`): find the view, find
  the component it mounts, and read its props interface.

## Step 2 — Confirm TypeScript types are exported

`ts-json-schema-generator` can only target **exported** types. Check each type
the test will validate:

- If a type is `interface Foo` or `type Foo` without `export`, add `export`.
- `TsSchemaSpec` raises if the requested type is missing from the generated
  document, so an unexported type fails loudly rather than validating against a
  permissive schema.

## Step 3 — Make the type strict enough to be worth validating

A schema is only as strong as the type it comes from. **A type whose fields are
all optional validates almost anything**, including the payload that omits them
— which defeats the point.

Tightening a props type is a **change to application code**, not to the test.
Make it a separate, reviewable commit and say so in the PR — do not fold it
silently into a spec-only change. If the type cannot be tightened right now,
say which fields are unconstrained rather than pretending the spec covers them.

Before writing the test, check the props type:

- Fields the server always sends must be **required**. If the server can send
  `null` (a new record's attributes, say), the type is `string | null`, not
  `string?`.
- An index signature (`[key: string]: …`) lets any key through. If the type
  needs one, keep the known keys required alongside it so a rename still fails.

## Step 4 — Point the spec at the TypeScript source

`match_schema` takes the source path — relative to Rails root — and the
exported type name, at the assertion itself:

```ruby
expect(props).to match_schema("app/javascript/MyComponent.tsx", "MyComponentProps")
```

Do not bind the schema in a `let` at the top of a describe block. Naming the
file and type at each assertion is what makes a wrong pairing visible in
review — a shared `let` is how a spec ends up asserting a sibling component's
type against this action.

When a spec file reads several types from the same source, bind the path to a
constant at the top of that spec rather than repeating it.

Generation is cached per **file**, so reading three types out of one `.ts`
costs one `npx` invocation, not three.

## Step 5 — Write the test

### Choosing the data source

| Action type                  | How to get the data                      |
| ---------------------------- | ---------------------------------------- |
| JSON action (`render json:`) | `response.parsed_body["key"]`            |
| HTML action with React props | `react_component_props("ComponentName")` |

`react_component_props` (from `ts_schema_spec/react_component_props`, included
in your `rails_helper`) parses the rendered `data-react-props` attributes and
returns **an array** — one entry per mount of that component on the page. It
needs `render_views`.

Pass the array straight to `match_schema`. It validates every entry and fails
on an empty collection, so a page that stopped rendering the component fails
instead of passing vacuously. Do not wrap it in `all` — `all` iterates zero
times on an empty array and asserts nothing.

### Test structure

Place the test in the existing controller spec file, in a new `describe` block.

```ruby
describe "the props handed to MyComponent" do
  render_views

  it "matches MyComponentProps" do
    # Build 2–3 records with meaningfully different traits so the schema is
    # exercised across its variation points: optional fields present vs
    # absent, different enum values, associations included vs nil.
    create(:factory_name, trait_a: true)
    create(:factory_name, :some_trait)

    get :show, params: { id: record.id }

    expect(response).to be_successful
    props = react_component_props("MyComponent")
    expect(props).to match_schema(MY_COMPONENT_TS, "MyComponentProps")
  end
end
```

### Rules for record creation

- Build **at least 2 records**, preferably 3, covering different states that
  affect serialization.
- Use existing factory traits. Do not define inline factory logic in the spec.
- If a field is a computed method, create records that exercise its non-trivial
  branch.

### Rules for assertions

- Always assert `response` is successful before checking shape.
- Validate with `match_schema` — do not hand-write field-by-field assertions
  for type shape; that is what the matcher is for.
- If the payload includes free-form metadata, assert its structure
  (`.to be_a(Hash)`, `.to include(...)`) rather than schema-validating it.
- If one action renders several distinct components, add a `match_schema`
  assertion per component.

## Step 6 — Verify the test passes

Run only the new describe block:

```
bundle exec rspec spec/controllers/my_controller_spec.rb --example "MyComponent"
```

If `ts-json-schema-generator` fails, the error names the cause. Common fixes:

- Type not exported (Step 2).
- Wrong path — it is relative to Rails root.
- A referenced type is not exported — export it too.

If the matcher fails, the message names the failing pointer and constraint, and
prints the payload, which points straight at the mismatch.

## Cost

Each distinct TypeScript **file** shells out to `npx ts-json-schema-generator`
once per suite run and is cached after that, however many types you read from
it. Validating the same type in many examples costs one generation.

## What NOT to do

- Do not write a test that only checks `response.status` — that belongs in a
  separate auth/routing spec.
- Do not duplicate an existing `match_schema` test covering the same action.
- Do not skip Step 3 and validate against an all-optional type; it will pass on
  a payload that is entirely wrong.

---
name: react-prop-type-spec
description: >
  Write or update RSpec tests that use match_schema to verify a Rails
  endpoint's payload matches the TypeScript type that consumes it. TRIGGER
  automatically (without being asked) whenever data crossing from Ruby to
  TypeScript is added or changed: adding a controller action; changing
  serialization in an existing one (helper method, as_json fields, included
  associations); adding or renaming a key in a render json: response or in
  props handed to a component; converting a Rails-mounted component from .jsx
  to .tsx; deleting a component's propTypes; or rendering an already-typed
  component from an action that has no match_schema spec. React is the common
  case, not a requirement — a Stimulus controller or a plain fetch client
  reading the payload counts the same. Invoked as /react-prop-type-spec.
---

A spec is owed any time data is handed from Ruby to TypeScript — not only when
something changes, and including where there is no Ruby diff at all. Two rules
keep that from multiplying:

- **Repeated mounts of one component are a single example.**
  `react_component_props` returns every mount and `match_schema` checks each.
- **Assert on the component Rails mounts.** A child receiving props from its
  parent is covered transitively; use the parent's props type.

## Step 0 — Already covered?

Covered = the spec for **the action rendering it** has a `match_schema` example
on that component. A sibling component, or the same component from another
action, is not coverage. Covered → stop.

## Step 1 — Find the TypeScript consumer

- **JSON** (`render json:`): find the `fetch`/`axios` call and the type it
  parses into.
- **HTML** (`react_component`): find the view, the component it mounts, and its
  props interface.

React is the common case, not a requirement — a payload read by a Stimulus
controller, a plain fetch client or any other TypeScript module is checked the
same way, via `response.parsed_body`. Only `react_component_props` is
React-specific.

No TypeScript consumer at all → exit the skill.

## Step 2 — Export the type

`ts-json-schema-generator` only targets exported types. Add `export` if it is
missing.

## Step 3 — Tighten the type

An all-optional type is satisfied by `{}`, so asserting on one asserts nothing.

- A field the server always sends: **required**.
- A field the server can send as null: `string | null`, not `string?`.
- A field with a fixed set of values: a literal union (`"draft" | "published"`),
  not `string`.
- An index signature or `Record<string, unknown>`: keep the keys the component
  actually reads **required alongside it**.

This edits application code rather than the test, so say that you did it. If
it cannot be tightened now, report which fields are unconstrained rather than
implying the spec covers them.

## Step 4 — Write the test

| Action | Data source |
| ------ | ----------- |
| `render json:` | `response.parsed_body["key"]` |
| `react_component` | `react_component_props("ComponentName")` |

`react_component_props` returns **an array**, one entry per mount, and needs
`render_views`. Pass it straight to `match_schema`: it validates every entry
and fails on an empty collection. Never wrap it in `all`, which iterates zero
times on an empty array and asserts nothing.

```ruby
describe "the props handed to MyComponent" do
  render_views

  it "matches MyComponentProps" do
    record = create(:factory_name, trait_a: true)
    create(:factory_name, :some_trait)

    get :show, params: { id: record.id }

    expect(response).to be_successful
    props = react_component_props("MyComponent")
    expect(props).to match_schema("app/javascript/MyComponent.tsx", "MyComponentProps")
  end
end
```

Name the file and type at the assertion. When several examples read the same
source, bind the path to a constant or a let variable.

Rules:

- Build multiple records with different traits, so optional fields, enum values
  and nil associations are actually exercised. Use existing factory traits.
- Assert `response` is successful before asserting shape.
- Let `match_schema` do the shape checking; no hand-written field assertions.
- Several components in one action: an example each, or one example marked
  `:aggregate_failures` if rendering the page is expensive — without it the
  first mismatch hides the rest.
- Do not write a spec that only checks `response.status`, and do not duplicate
  an existing `match_schema` for the same action.
- **When it fails, fix Rails.** The type is the consumer's contract: if the
  component needs a field, the payload is wrong. Loosening the type is always
  the quicker route to green, and it is how this stops catching anything.

## Step 5 — Run it

```
bundle exec rspec spec/controllers/my_controller_spec.rb --example "MyComponent"
```

## When a rule here does not fit

The gem's README carries the reasoning behind these rules, plus troubleshooting
for generator errors. It ships inside the gem, so this reads the version the
app actually has:

```
cat "$(bundle show ts_schema_spec)/README.md"
```

Sections: **Best practices**, **Gotchas**, **Troubleshooting**. If the command
fails, carry on — the rules above stand on their own.

---
name: react-prop-type-spec
description: >
  Write or update RSpec tests that use match_schema to verify a Rails
  endpoint's payload matches the TypeScript type the React side consumes.
  TRIGGER automatically (without being asked) whenever: adding a controller
  action; changing serialization in an existing one (helper method, as_json
  fields, included associations); adding or renaming a key in a render json:
  response or in props passed to a React component; converting a
  Rails-mounted component from .jsx to .tsx; deleting a component's
  propTypes; or rendering an already-typed component from an action that has
  no match_schema spec. Covers both render json: and
  react_component props. Invoked as /react-prop-type-spec.
---

This is a coverage rule, not only a change-triggered one — the spec is owed
wherever the Rails-renders-React pairing exists, including with no Ruby diff at
all. Three rules keep that from multiplying:

- **Repeated mounts of one component are a single example.**
  `react_component_props` returns every mount and `match_schema` checks each.
- **Distinct components each get their own assertion**, one per component the
  action renders.
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

Fields the server always sends should be required; a field that can be null is
`string | null`, not `string?`; an index signature keeps the known keys
required alongside it — likewise `Record<string, unknown>`, which is the
same hole by another name: whatever the component actually reads out of that
bag belongs in the type. An all-optional type is satisfied by `{}`, so asserting
on one passes while catching nothing — which is worse than no spec, because it
reads as coverage.

Tightening a props type edits application code rather than the test, so say
that you did it. If it cannot be tightened now, report which fields are
unconstrained rather than implying the spec covers them.

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
    create(:factory_name, trait_a: true)
    create(:factory_name, :some_trait)

    get :show, params: { id: record.id }

    expect(response).to be_successful
    props = react_component_props("MyComponent") # an array, one entry per call site
    expect(props).to match_schema("app/javascript/MyComponent.tsx", "MyComponentProps")
  end
end
```

Name the file and type at the assertion. When several examples read the same
source, bind the path to a constant or a let variable.

Rules:

- When appropriate, build multiple records with different traits, so optional
  fields, enum values and nil associations are actually exercised. Use existing
  factory traits where available.
- Assert `response` is successful first, to catch redirects and error
  responses rather than debugging them as schema failures.
- Let `match_schema` do the shape checking; no hand-written field assertions.
- Several components in one action: an example each, or one example marked
  `:aggregate_failures` if rendering the page is expensive — without it the
  first mismatch hides the rest.
- Do not write a spec that only checks `response.status`, and do not duplicate
  an existing `match_schema` for the same action.

## Step 5 — Run it

```
bundle exec rspec spec/controllers/my_controller_spec.rb --example "MyComponent"
```

Generation errors name their cause — usually an unexported type, or a path that
is not relative to Rails root. A matcher failure names the failing pointer and
prints the payload.

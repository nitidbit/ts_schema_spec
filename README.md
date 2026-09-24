# ts_schema_spec

Add tests to your Ruby test suite that assert a JSON payload generated in Ruby
matches the TypeScript type of the consumer.

Built for RSpec, but could be ported to other test frameworks (Minitest, etc.).

`react_component_props`, an optional React-specific helper, reads props out of
rendered mounts.

React is the case this gem was built for, not a requirement. `match_ts_schema`
checks any payload against any exported TypeScript type, so a Stimulus
controller or a plain fetch client works the same way.

## Install

```ruby
# Gemfile
gem "ts_schema_spec", group: :test
```

This gem requires ts-json-schema-generator, resolved from your project's
`node_modules`:

```
npm install --save-dev ts-json-schema-generator
```

Add the following to your test suite:

```ruby
# spec/rails_helper.rb
require "ts_schema_spec/rspec"
require "ts_schema_spec/react_component_props" # optional, for parsing props from rendered HTML. See below.

RSpec.configure do |config|
  config.include TsSchemaSpec::ReactComponentProps
end
```

### Path aliases

If your TypeScript imports through aliases (`@/components/Foo`), point the
generator at your tsconfig:

```ruby
# spec/rails_helper.rb
TsSchemaSpec.configure do |config|
  config.tsconfig = Rails.root.join("tsconfig.json").to_s
  config.generator_args = []  # anything else to pass through
end
```

**This is not optional decoration.** An import the generator cannot resolve
does not fail — it becomes an empty schema, and an empty schema validates
anything:

```json
"role": {}
```

So an aliased type without a tsconfig gives you a green spec that accepts a
string, a number or null where an object was declared. If any type you assert
on imports through an alias, set this.

### The agent skill

The gem ships the skill that teaches an agent when one of these specs is owed
and how to write it. Claude Code reads skills from the working tree, so it has
to be copied in and committed:

```
RAILS_ENV=test bundle exec rake ts_schema_spec:install_skill
```

`RAILS_ENV=test` is required when the gem is in `group: :test`, as above.

It lands in `.claude/skills/ts-schema-spec/SKILL.md`, stamped with the
gem version. To keep the skill in sync with the gem version:

```ruby
# spec/ts_schema_spec_skill_spec.rb
it "has the skill matching the installed gem" do
  expect { TsSchemaSpec::Skill.check!(Rails.root) }.to_not raise_error
end
```

Versions up to 0.5.4 named the skill `react-prop-type-spec`. After reinstalling,
delete `.claude/skills/react-prop-type-spec/`.

## Use

### A JSON endpoint

```ruby
it "matches AccountPayload" do
  create(:account, :with_roles)
  create(:account, :unassigned)

  get :index, format: :json

  expect(response).to be_successful
  expect(response.parsed_body["accounts"])
    .to match_ts_schema("app/javascript/types/account.ts", "AccountPayload")
end
```

### Props from an HTML mount

`react_component_props` parses the rendered `data-react-props` attributes and
returns **an array** — one entry per mount of that component on the page. It
needs `render_views`.

It assumes [react-rails](https://github.com/reactjs/react-rails) conventions:
`data-react-class` and `data-react-props` on the mount element. A namespaced
class matches on its trailing segment, so `admin/SidebarNav` and
`Admin.SidebarNav` both answer to `"SidebarNav"`.

Other integrations mount differently — react_on_rails uses its own attributes
— and against those it finds nothing and reports an empty collection rather
than a missing-attribute error. Supporting another convention is a small
change to one file; open a PR if you need it.

```ruby
describe "the props handed to RoleMatrix" do
  render_views

  role_matrix = "app/javascript/components/roles/RoleMatrix.tsx"

  it "matches RoleMatrixProps" do
    account = create(:account, :with_roles)

    get :show, params: { id: account.id }

    expect(response).to be_successful
    props = react_component_props("RoleMatrix")
    expect(props).to match_ts_schema(role_matrix, "RoleMatrixProps")
  end
end
```

`match_ts_schema` accepts a hash or an array of hashes. Given an array, it
validates every item and fails on an empty one — in both directions, so
`to_not match_ts_schema` does not pass vacuously either. A page that stopped
rendering the component fails rather than passing silently. The alternative
construction, `expect(props).to all match_ts_schema(...)`, would pass on an
empty array.

## API

| Call                                    | Returns                                                     |
| --------------------------------------- | ----------------------------------------------------------- |
| `TsSchemaSpec.schema_for(path, type)`   | a `JSONSchemer` schema scoped to that exported type          |
| `match_ts_schema(path, type)`           | matcher; validates a hash, or every item of an array         |
| `react_component_props(name[, html])`   | array of props hashes, one per mount                         |
| `TsSchemaSpec::Skill.check!(root)`      | raises if the installed skill is stale or missing            |
| `TsSchemaSpec.configure`                | sets `tsconfig` and extra generator arguments                |
| `TsSchemaSpec.clear_cache!`             | drops the generated-schema cache                             |

`match_ts_schema` was called `match_schema` before 0.6.1. The old name still
works but is deprecated and will be removed.

`path` is resolved from wherever the suite runs, which is the Rails root in
practice. Name the type at the assertion, so an example says which type it is
checking. When several examples read the same source, bind the path to a local
variable or a `let` — a constant assigned inside a `describe` block is global,
so two spec files that both use one will collide.

`schema_for` stays public, but is not needed when using the RSpec matcher,
which calls it internally.

## What a failure looks like

```
expected the payload to match Role (app/javascript/types/role.ts), but:
 - /id: value at `/id` is not a number
 - /created_at: object property at `/created_at` is a disallowed additional property
 - (root): object at root is missing required properties: shortcode

Payload was:
{
  "id": "1",
  "name": "Nurse",
  "created_at": "2026-09-11"
}
```

## Best practices

**Build records that cover the variations.** One response only exercises the
branches it took. When the type has optional fields, enum values or nullable
associations, create as many records, with as many different traits, as it
takes to put those branches in the payload.

**Tighten the type first.** A schema is only as strong as the type it comes
from, and an all-optional type is satisfied by `{}` — asserting against one
passes while catching nothing, which is worse than no spec, because it reads
as coverage.

- A field the server always sends: **required**.
- A field that can be null: `string | null`, not `string?`.
- A field with a fixed set of values: a literal union
  (`"draft" | "published"`), not `string` — which catches a typo and a value
  the consumer was never taught about.
- An index signature or `Record<string, unknown>`: declare the keys the
  component actually reads, required, alongside it.

A literal union only stays honest while it tracks the Ruby enum it mirrors,
which needs some way of sharing constants from Ruby into TypeScript — a
generator, a shared JSON file, whatever suits your repo. That is outside this
gem's scope, but with one in place, and a record for each value in the
example, a drifted union fails here rather than in the browser.

**Pass the whole collection.** `match_ts_schema` validates every item and fails
on an empty one. Avoid `expect(props).to all match_ts_schema(...)`, which
passes on an empty array, hiding an issue with generation.

**Assert the response is successful first.** Otherwise a redirect or a 500
arrives as a schema failure, and you debug the wrong thing.

**Let the matcher do the shape checking.** Hand-written field assertions
alongside it duplicate what the type already says, and go stale separately.

**When it fails, fix Rails.** The type is the consumer's contract: if the
component needs a field, the payload is wrong. Loosen the type only when the
component genuinely does not need what it declares — loosening is always the
quicker route to green, and it is how this stops catching anything.

## Gotchas

**Undeclared keys fail.** `ts-json-schema-generator` emits
`additionalProperties: false`, so a payload carrying a key the TypeScript does
not declare is an error, not a warning. That is deliberate — it catches Rails
sending something nobody typed — but expect it when an `as_json` emits
timestamps the React side ignores. Fix by declaring the field or narrowing the
`only:`.

## Cost

One `npx ts-json-schema-generator` run per source file. Generated schemas are
cached in memory, keyed by the file and the generator arguments, so reading
three types out of one `.ts` costs one run rather than three, and changing
`TsSchemaSpec.configure` regenerates rather than serving a stale schema.

The cache lives in the process, so parallel test workers each pay for it once.

## Troubleshooting

| Symptom                                              | Cause                                                          |
| ---------------------------------------------------- | -------------------------------------------------------------- |
| `GenerationError: ... Is it exported?`               | the type has no `export`, or the name is misspelled             |
| `GenerationError` listing a rerunnable command       | run it — the generator's own stderr is in the message           |
| passes against an obviously wrong payload            | the type is all-optional, or an unresolved import became `{}`   |
| `could not run npx ts-json-schema-generator`         | the generator is not in your `node_modules`                     |
| `disallowed additional property`                     | see above — the payload sends what TypeScript does not declare  |
| `has no data-react-props attribute`                  | hand-written markup, or a mount from another integration        |

## What this can't catch

Worth knowing before you rely on it.

**Coverage is discipline-dependent.** This protects the actions somebody wrote
a spec for; an uncovered endpoint is exactly as exposed as before. That is what
the skill is for, and it is convention rather than enforcement.

**It only checks what TypeScript declares.** If Rails *intends* to send a field
nobody typed — say `as_json(only:)` carrying a misspelled attribute, which
Rails drops silently — no generated schema requires it, so nothing fails. A
structured serializer catches that class of mistake; this does not.

## Alternatives

An alternate methodology is to generate the TypeScript types from Ruby.

[Typelizer](https://typelizer.dev/) and
[types_from_serializers](https://github.com/ElMassimo/types_from_serializers)
make Ruby canonical and generate the types, so drift becomes structurally
impossible rather than something you test for. That beats this.

They need serialization to exist somewhere nameable — they introspect Alba,
AMS, Oj, Panko or oj_serializers. An app that is plain `as_json` and
`render json:`, deciding payload shapes inline at each call site, has no
artifact for a generator to read. This gem is for that case: if a shape only
exists at its call site, the only way to learn it is to run the action and
look.

The other camp — [json_matchers](https://github.com/thoughtbot/json_matchers),
committee, rswag — validates against a hand-maintained JSON Schema file. That
is a third artifact to keep in sync with both sides, which is the same drift
problem relocated.

One gap stays open whichever you pick: `react_component` props. Typelizer
types serializer output and knows nothing about the outer props object a view
assembles, so nothing generated from your serializers covers it.

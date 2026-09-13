# ts_schema_spec

Add tests to your ruby test suite that assert that a JSON
payload generated in Ruby matches the consumer's Typescript type.

Build for Rspec, but could be ported to other test frameworks (Minitest, etc.)

A React-specific provided helper, `react_component_props`, reads props out of
rendered mounts.

React is the case this gem was built for, not a requirement. `match_schema` checks
any payload against any exported TypeScript type, so a Stimulus controller or
a plain fetch client works the same way.
## Install

```ruby
# Gemfile
gem "ts_schema_spec", github: "nitidbit/ts_schema_spec", tag: "v0.5.1", group: :test
```

This gem requires ts-json-schema-generator, resolved from your
project's `node_modules`.

```
npm install --save-dev ts-json-schema-generator
```

Add the following ruby code to your test suite

```ruby
# spec/rails_helper.rb
require "ts_schema_spec/rspec"
require "ts_schema_spec/react_component_props" # optional, for parsing props from rendered html. see below.

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

It lands in `.claude/skills/react-prop-type-spec/SKILL.md`, stamped with the
gem version. To keep the skill in sync with the gem version:

```ruby
# spec/ts_schema_spec_skill_spec.rb
it "has the skill matching the installed gem" do
  expect { TsSchemaSpec::Skill.check!(Rails.root) }.to_not raise_error
end
```

## Use

### A JSON endpoint

```ruby
ACCOUNT_TS = "app/javascript/types/account.ts"

it "matches AccountPayload" do
  get :index, format: :json

  expect(response).to be_successful
  expect(response.parsed_body["accounts"]).to match_schema(ACCOUNT_TS, "AccountPayload")
end
```

### Props from an HTML mount

`react_component_props` parses the rendered `data-react-props` attributes and
returns **an array** — one entry per mount of that component on the page. It
needs `render_views`.

It assumes [react-rails](https://github.com/reactjs/react-rails) conventions —
`data-react-class` and `data-react-props` on the mount element. A namespaced
class matches on its trailing segment, so `admin/SidebarNav` and
`Admin.SidebarNav` both answer to `"SidebarNav"`. Other
integrations mount differently (react_on_rails uses its own attributes), and
against those it finds nothing and reports an empty collection rather than a
missing-attribute error. Supporting another convention is a small change to one
file; open a PR if you need it.

```ruby
describe "the props handed to RoleMatrix" do
  render_views

  role_matrix = "app/javascript/components/roles/RoleMatrix.tsx"

  it "matches RoleMatrixProps" do
    account = create(:account, :with_roles)
    create(:account, :unassigned)

    get :show, params: { id: account.id }

    expect(response).to be_successful
    props = react_component_props("RoleMatrix")
    expect(props).to match_schema(role_matrix, "RoleMatrixProps")
  end
end
```

`match_schema` accepts a hash or an array of hashes. If given an array,
`match_schema` validates every item and fails on an
empty array.  This means that a page that stopped rendering the component fails
rather than passing silently.  An alternative construction,
`expect(props).to all match_schema(...)` would pass on an empty array.

## API

| Call                                    | Returns                                                |
| --------------------------------------- | ------------------------------------------------------ |
| `TsSchemaSpec.schema_for(path, type)`   | a `JSONSchemer` schema scoped to that exported type     |
| `match_schema(path, type)`              | matcher; validates an object, or every item of a collection |
| `react_component_props(name[, html])`   | array of props hashes, one per mount                    |
| `TsSchemaSpec::Skill.check!(root)`      | raises if the installed skill is stale or missing       |
| `TsSchemaSpec.configure`                | `tsconfig` and extra generator arguments                |
| `TsSchemaSpec.clear_cache!`             | drops the per-file schema cache                         |

`path` is relative to Rails root, and goes at the assertion rather than in a
`let` — a schema bound once at the top of a describe block is how you end up
asserting one component's type against another's action. When several examples
read the same source, bind the path itself to a constant.

`schema_for` stays public for use outside RSpec; the matcher calls it for you,
and generation is cached per file, so naming the same source in twenty
examples costs one `npx` run.

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

## Notes and Reccomendations

**Be Through.** Especially when your type has optional fields, enum values, associations,
etc., build as many records as needed, with different traits, so that all variations get exercised.

**Undeclared keys fail.** `ts-json-schema-generator` emits
`additionalProperties: false`, so a payload carrying a key the TypeScript does
not declare is an error, not a warning. That is deliberate — it catches Rails
sending something nobody typed — but expect it when an `as_json` emits
timestamps the React side ignores. Fix by declaring the field or narrowing the
`only:`.

**An all-optional type asserts almost nothing.** A schema is only as strong as
the type it comes from; `shortcode?: string` passes whether the key is there
or not. If the server always sends a field, make it required, and use
`string | null` rather than `?` for a field that can be null. Tightening a
props type is an application change — give it its own commit.

## Cost

Schema generation is cached, so that... this section is confusing, fix it...
One `npx ts-json-schema-generator` invocation per **file** per suite run,
cached by path — reading three types out of one `.ts` costs one parse, not
three. The cache is per process, so parallel workers each pay it once.

## Troubleshooting

| Symptom                                              | Cause                                                        |
| ---------------------------------------------------- | ------------------------------------------------------------ |
| `GenerationError: ... Is it exported?`               | the type has no `export`, or the name is misspelled           |
| `GenerationError` listing a rerunnable command       | run it — the generator's own stderr is in the message         |
| passes against an obviously wrong payload            | the type is all-optional, or an unresolved import became `{}` |
| `could not run npx ts-json-schema-generator`         | the generator is not in your `node_modules`                   |
| `disallowed additional property`                     | see above — the payload sends what TypeScript does not declare |

## What this can't catch

Worth knowing before you rely on it.

**Coverage is discipline-dependent.** This protects the actions somebody wrote
a spec for; an uncovered endpoint is exactly as exposed as before. That is what
the skill is for, and it is convention rather than enforcement.

**It only checks what TypeScript declares.** If Rails *intends* to send a field
nobody typed — say `as_json(only:)` carrying a misspelled attribute, which
Rails drops silently — no generated schema requires it, so nothing fails. A
structured serializer catches that class of mistake; this does not.

**One payload shape per example.** A single response only exercises the
branches it took. Nullable fields, empty collections and conditional
associations need records built to hit them.

## Alternatives

An alternate methodology is to generate Typescript types from ruby.

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

Even with generated types, `react_component` props stay uncovered: Typelizer
types serializer output and knows nothing about the outer props object
assembled in a view. That part is this gem's permanently.


That part is this gem's permanently.??? what does that sentence even mean?

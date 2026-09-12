# frozen_string_literal: true

module TsSchemaSpec
  # Repo-level generator settings. `tsconfig` matters more than it looks: an
  # import the generator cannot resolve becomes an empty schema, which
  # validates anything, so a repo using path aliases needs this set or its
  # aliased types silently assert nothing.
  class Config
    attr_accessor :tsconfig, :generator_args

    def initialize
      @generator_args = []
    end

    def to_args
      args = []
      args += ["--tsconfig", tsconfig.to_s] if tsconfig
      args + Array(generator_args)
    end
  end
end

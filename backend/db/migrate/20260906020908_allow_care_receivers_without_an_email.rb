# frozen_string_literal: true

# A care receiver an adult child sets up may have no email address at all.
#
# That is the point rather than an omission. The flow deliberately never asks
# for one: with no address there is no lookup, so no way to discover whether
# somebody already uses Remindly, and no branch that behaves differently for an
# address in use — which would be an enumeration oracle wearing a setup form.
# It also matches the scene. Somebody standing in their mother's kitchen should
# not have to know which of her three addresses she still reads.
#
# The column has never been null in practice, so this only widens what the
# database will accept. The uniqueness rule that matters is unchanged: SQLite
# treats NULLs as distinct in a unique index, so any number of accounts may have
# no address while no two may share one.
class AllowCareReceiversWithoutAnEmail < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :email, true
  end
end

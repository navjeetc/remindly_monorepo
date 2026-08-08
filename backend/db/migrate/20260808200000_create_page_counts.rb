## An aggregate tally of public page views, deliberately built so that no row
## describes a person.
##
## The public pages set no analytics cookies and write no Ahoy visit, which is
## what makes the privacy policy true — and the cost of that was total blindness
## to whether any marketing effort worked. A forum post in August 2026 produced
## no signups, and there was no way to tell whether it had sent nobody or sent
## a hundred people who bounced. Those call for opposite responses.
##
## The unit of storage is a day, not a visit: one row per
## (day, path, referrer host, campaign tag, bot) with a counter. There is no
## visitor id, no IP address, no user agent and no cookie, so the table cannot
## be turned back into individual people even in principle.
##
## Every dimension defaults to "" rather than NULL. SQLite treats NULLs as
## distinct in a unique index, so a nullable column would defeat the ON CONFLICT
## clause the counter relies on and quietly write a new row per request.
class CreatePageCounts < ActiveRecord::Migration[8.0]
  def change
    create_table :page_counts do |t|
      t.date :day, null: false
      t.string :path, null: false
      t.string :referrer_host, null: false, default: ""
      t.string :source, null: false, default: ""
      t.boolean :bot, null: false, default: false
      t.integer :count, null: false, default: 0

      t.timestamps
    end

    add_index :page_counts,
      [ :day, :path, :referrer_host, :source, :bot ],
      unique: true,
      name: "index_page_counts_on_dimensions"

    # The prune job and every admin query filter by day.
    add_index :page_counts, :day
  end
end

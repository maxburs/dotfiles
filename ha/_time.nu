# How the commands show times and count things per day.

export const TIME_FORMAT = '%Y-%m-%d %a %H:%M:%S'
export const DAY_FORMAT = '%Y-%m-%d %a'

# Counts per local day from `first` to `last`, including days with none: the
# date, a column per entry in `columns`, and the total. Each row of `rows` is a
# {time, column} record, counted on the day of its time.
export def count-by-day [
  rows: table
  columns: list<string>
  first: datetime
  last: datetime
]: nothing -> table {
  let first_day = $first | format date '%Y-%m-%d'
  let last_day = $last | format date '%Y-%m-%d'
  # seq date counts down when the end is before the beginning.
  if $first_day > $last_day { return [] }

  let by_day = $rows | group-by { $in.time | format date '%Y-%m-%d' }
  seq date --begin-date $first_day --end-date $last_day
  | each {|day|
      let day_rows = $by_day | get -o $day | default []
      $columns
      | reduce --fold {date: ($day | into datetime | format date $DAY_FORMAT)} {|column, row|
          $row | insert $column ($day_rows | where column == $column | length)
        }
      | insert total ($day_rows | length)
    }
}

module TabularImporter
  class HeaderMatcher
    def self.call(headers:, definition:)
      used = Set.new

      Array(headers).each_with_index.each_with_object({}) do |(header, index), mapping|
        column = definition.columns.find do |candidate|
          !used.include?(candidate.key) && candidate.matches_header?(header)
        end
        next unless column

        mapping[index.to_s] = column.key
        used << column.key
      end
    end
  end
end

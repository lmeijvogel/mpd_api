class MpdResponse
  def initialize(response_text)
    @response_text = response_text[0] =~ /\AOK/ ? response_text[1..-1] : response_text
  end

  def read_value(field_name, default: nil)
    regex = %r[^#{field_name}: (.*)]

    matching_lines = @response_text.grep(regex)

    if matching_lines.none? && default
      return default
    end

    matches = matching_lines[0].match(regex)

    matches[1]
  end

  def lines
    @response_text
  end

  def count
    lines.count
  end

  def slice_before(regex)
    @response_text.slice_before(regex).map {|part| MpdResponse.new(part) }
  end

  def to_s
    "MpdResponse:\n  " + @response_text.join("\n  ")
  end
end

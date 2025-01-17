require "compiler/crystal/syntax"
require "json"

class TestCase
  property name : String
  property source_code : Array(String)
  property snippet : String
  property start_location : Crystal::Location?
  property end_location : Crystal::Location?

  def initialize(
    name : String,
    source_code : Array(String),
    snippet : String,
    start_location : Crystal::Location?,
    end_location : Crystal::Location?
  )
    @name = name
    @source_code = source_code
    @snippet = snippet
    @start_location = start_location
    @end_location = end_location
  end

  def test_code : String
    start_location = self.start_location
    end_location = self.end_location
    return snippet if start_location.nil? || end_location.nil?

    start_column_index = start_location.column_number - 1
    start_line_index = start_location.line_number - 1
    end_line_index = end_location.line_number - 1

    source_code[start_line_index..end_line_index]
      .map { |line| line[start_column_index..-1]? || "" }
      .join("\n")
  end

  def to_json(json)
    json.object do
      json.field "name", name
      json.field "test_code", test_code
      json.field "status", nil
      json.field "message", nil
      json.field "output", nil
    end
  end
end

class TestVisitor < Crystal::Visitor
  property tests, breadcrumbs, source_code

  def initialize(source_code : Array(String))
    @tests = Array(TestCase).new
    @breadcrumbs = Array(String).new
    @source_code = source_code
  end

  def current_test_name_prefix
    breadcrumbs.join(" ")
  end

  def visit(node : Crystal::Call)
    case node.name
    when "describe"
      handle_visit_describe_call(node)
    when "it"
      handle_visit_it_call(node)
    when "pending"
      handle_visit_it_call(node)
    end

    false
  end

  def end_visit(node : Crystal::Call)
    case node.name
    when "describe"
      handle_end_visit_describe_call(node)
    end
  end

  def visit(node)
    true
  end

  private def handle_visit_describe_call(node : Crystal::Call)
    @breadcrumbs << node.args[0].not_nil!.as(Crystal::StringLiteral).value
    accept(node.block.not_nil!)
  end

  private def handle_end_visit_describe_call(node : Crystal::Call)
    breadcrumbs.pop
    return true
  end

  private def handle_visit_it_call(node : Crystal::Call)
    label = node.args[0].not_nil!.as(Crystal::StringLiteral).value
    name = "#{current_test_name_prefix} #{label}"

    snippet = node.block.not_nil!.body.to_s
    start_location = node.block.not_nil!.body.location
    end_location = node.block.not_nil!.body.end_location
    @tests << TestCase.new(name, source_code, snippet, start_location, end_location)
  end
end

test_file = ARGV[0]?
output_file = ARGV[1]?

unless test_file && output_file
  puts <<-USAGE
    Usage:
    > scaffold_json <spec test file> <output json file>
    USAGE
  exit 1
end

puts "* Reading spec file: #{test_file} 📖"

test_file_content = File
  .read(test_file)

parser = Crystal::Parser.new(test_file_content)
ast = parser.parse

visitor = TestVisitor.new(test_file_content.lines)
visitor.accept(ast)

scaffold =
  JSON.build do |json|
    json.object do
      json.field "version", 2
      json.field "status", nil
      json.field "message", nil
      json.field "tests", visitor.tests
    end
  end

puts "* Writing scaffold json to: #{output_file} 🖊"

File.write(output_file, scaffold)
puts "* All done converting spec to scaffold json 🏁"

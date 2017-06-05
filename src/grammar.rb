

Token = Struct.new(:token, :data, :start, :finish)

class Token
  def inspect
    if data
      "#{token.inspect}(#{data})"
    else
      token.inspect
    end
  end
end

BREAK = ".{}()[]<> \t\n:;".chars

class Tokenizer

  def initialize(text)
    @text = text
    @index = 0
    @tokens = []
    @last = 0
  end

  def char
    @text[@index]
  end

  def advance
    @index += 1
  end

  def done?
    @index == @text.length
  end

  def save(token, data: nil)
    @tokens << Token.new(token, data, @last, @index)
    @last = @index
  end

  def tokens
    until done?
      case
      when char == '.'
        advance
        if BREAK.include? char
          save :dot
        else
          ident = read_ident
          save :dotaccess, data: ident
        end
      when char == '['
        advance
        save :open_square
      when char == ']'
        advance
        save :close_square
      when char == '<'
        advance
        save :open_angle
      when char == '>'
        advance
        save :close_angle
      when char == "\n"
        advance
        save :newline
      when char == ':'
        advance
        save :colon
      when char == ';'
        advance
        save :semicolon
      when char == '('
        advance
        save :open_round
      when char == ')'
        advance
        save :close_round
      when char == '"'
        string = read_quotes(char)
        save :string, data: string
      when (char == ' ' or char == "\t")
        advance
        @last = @index
      else
        ident = read_ident
        save :ident, data: ident
      end
    end

    @tokens
  end

  def read_ident
    store = ''
    until done? or BREAK.include?(char)
      store += char
      advance
    end
    store
  end

  def read_quotes(quote)
    advance
    store = ''
    while (not done?) and (char != quote)
      store += char
      advance
    end
    advance
    store
  end
end

class Ast

  # token is only used to pun with Tokens
  attr_accessor :children, :kind, :token

  def initialize(children, kind)
    @kind = kind
    @children = children
  end

  def inspect
    "#{kind}#{children}"
  end
end

class Parens < Ast
  def initialize(children)
    @kind = :parens
    @children = children
  end
end

class Block < Ast
  attr_reader :arguments
  
  def initialize(children, arguments)
    @children = children
    @arguments = arguments
    @kind = :block
  end

  def inspect
    "#{kind}#{arguments}#{children}"
  end
end


class Grammar

  def initialize(tokens)
    @ast = Ast.new(tokens, :root)
  end

  def ast
    collect do |x|
      parentheses x
    end
    collect do |x|
      lambdas x
    end
    @ast
  end

  def collect
    yield @ast
    rest = @ast.children.clone
    until rest.empty?
      ast = rest.pop 
      
      if ast.class == Ast # otherwise it's a token
        yield ast
        ast.children.each { |a| rest << a }
      end
    end
  end

  # states
  SEARCHING = 0
  ARGUMENTS = 1
  LINES = 2
  def lambdas(ast)

    count = 0
    values = []
    state = SEARCHING

    # used to construct the block:
    arguments = []
    lines = []
    line = []

    ast.children.each do |child|
      case state
      when SEARCHING
        if child.token == :colon
          state = ARGUMENTS
        elsif child.token == :open_square
          state = LINES
        else
          values << child
        end
      when ARGUMENTS
        if child.token == :open_square
          count = 1
          state = LINES
        elsif child.token == :ident
          arguments << child
        else
          error_ast(child, 'expected an identifier when \
                            listing arguments to a block')
        end
      when LINES
        if child.token == :open_square
          count += 1
        elsif child.token == :close_square
          raise 'Got unexpected close square bracket' if count.zero?
          count -= 1
        end

        if count.zero?
          lines << Parens.new(line) unless line.empty?
          values << Block.new(lines, arguments)
          line = []             # just added these: -- check in the future
          state = SEARCHING
        elsif child.token == :newline
          lines << Parens.new(line) unless line.empty?
          line = []
        else
          line << child
        end
      end
    end
    raise 'Got unexpected open square bracket' if count != 0

    ast.children = values
  end

  # states
  # SEARCHING = 0
  # LINES = 2
  def parentheses(ast)
    count = 0
    values = []
    line = []
    state = SEARCHING
    ast.children.each do |child|
      case state
      when SEARCHING
        if child.token == :open_round
          count = 1
          state = LINES
        else
          values << child
        end
      when LINES
        if child.token == :open_round
          count += 1
        elsif child.token == :close_round
          raise 'Got unexpected close parenthesis' if count.zero?
          count -= 1
        end

        p child, count
        if count.zero?
          values << Parens.new(line) unless line.empty?
          line = []
          state = SEARCHING
        else
          line << child
        end
      end
    end
    raise 'Got unexpected open parenthesis' if count != 0
    ast.children = values
  end
end

def error_ast(ast, reason)
  p 'Error:', ast, reason
end

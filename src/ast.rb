
# Token = Struct.new(:token, :data, :start, :finish)

def is_ident(tok, name)
  return false if tok.nil?
  tok.token == :ident and tok.data == name
end

Separator = Struct.new(:ast, :post)

class Token

  attr_accessor :type, :data, :token, :start, :finish

  def initialize(token, data, start, finish)
    @token = token
    @data = data
    @start = start
    @finish = finish
  end

  def inspect
    if data
      "#{token.inspect}(#{data})"
    else
      token.inspect
    end
  end

  def inspect_types
    if data
      "#{token}(#{data})" + "::#{type}"
    else
      token.inspect + "::#{type}" # do you need this?
    end
  end

end

class Ast < Token

  attr_accessor :children, :kind

  def initialize(children, kind)
    @kind = kind
    @children = children

    @start = @children.first.start
    @finish = @children.last.finish
  end

  def inspect
    "#{kind}#{children}"
  end

  def inspect_types
    "#{kind}[#{children.map{|x| x.inspect_types}.join(", ")}]" + "::#{type}"
  end

  def iterate
    # do nothing
    # only used in Parens
  end

  def iterate_follow
    # again nothing
  end

  def all_iterables(&block)
    @children.map(&block)
  end

  def collect(cls: Ast, post:nil)
    yield self if self.is_a?(cls)

    rest = self.all_iterables { |x| x }
    until rest.empty?
      ast = rest.pop

      # This little bit is used to have
      # callbacks after the completion of an
      # ast's children
      #
      # Perhaps there is a cleaner way to do this
      # (certainly with recursion) but it's not
      # THAT ugly so we'll leave it in for now.
      if ast.is_a?(Separator)
        ast.post.call(ast.ast) if ast.post
      end

      if ast.is_a?(cls) # otherwise it's a token
        yield ast
      end

      if ast.is_a?(Ast)
        rest << Separator.new(ast, post)
        ast.all_iterables { |a| rest << a }
      end

      # also iterate over let_in values
      if ast.is_a?(Let_in)
        rest << ast.value
      end
    end
  end

end

class Root < Ast
  def initialize(children)
    @kind = :root
    @children = children

    if @children.first
      @start = @children.first.start
      @finish = @children.last.finish
    else
      @start = 0
      @finish = 0
    end
  end

  def iterate(&block)
    @children.map!(&block)
    @children.select! {|c| not c.nil?}
  end

  def iterate_follow
    yield
    @children.select! {|c| not c.nil?}
  end

end

class Dot_access < Root
  attr_reader :name

  def initialize(name_tok, child)
    @children = [child]
    @name = name_tok.data
    @start = child.start
    @finish = name_tok.finish
  end

  def child
    @children[0]
  end

  def inspect
    "#{child.inspect}.#{name}"
  end

  def inspect_types
    "#{child.inspect_types}.#{name}::#{type}"
  end
end

class Parens < Root
  def initialize(children, backup_child)
    @kind = :parens
    @children = children

    @start = (@children.first || backup_child).start
    @finish = (@children.last || backup_child).finish
  end

  def inspect
    inner = @children.map {|x| x.inspect}.join(" ")
    "(#{inner})"
  end

  def inspect_types
    inner = @children.map {|x| x.inspect_types}.join(" ")
    "(#{inner})::#{type}"
  end
end

class Block < Ast
  attr_reader :arguments

  def initialize(children, arguments, backup_child)
    @children = children
    @arguments = arguments
    @kind = :block

    @start = (@arguments.first || @children.first || backup_child).start
    @finish = (@children.last || backup_child).finish
  end

  def inspect
    "#{kind}#{arguments}#{children}"
  end

  def inspect_types
    args = arguments.map{|x| x.inspect_types}.join(", ")
    chlds = children.map{|x| x.inspect_types}.join(", ")
    "#{kind}[#{args}][#{chlds}]::#{type}"
  end
end

class Let_in < Block
  attr_reader :name, :value

  def initialize(name_tok, value, children)
    @children = children
    @name = name_tok.data
    @value = value
    @kind = :let_in

    @start = name_tok.start
    @finish = (children.last || name_tok).finish
  end

  def inspect
    "let_in #{name} #{value.inspect} #{children}"
  end

  def inspect_types
    chlds = children.map{|x| x.inspect_types}.join(", ")

    "let_in(#{name} #{value.inspect_types} #{chlds})::#{type}"
  end
end


class Object_literal < Ast
  attr_reader :fields

  def initialize(field_map)
    # we don't need a backup child because v has >0 elements.
    field_map.each { |k, v| field_map[k] = Parens.new(v, nil) }
    @fields = field_map

    @start = @fields.values.map { |x| x.start }.min
    @finish = @fields.values.map { |x| x.finish }.max
  end

  def all_iterables
    @fields.map {|_name, ast| yield ast }
  end

  def inspect
    inner = @fields.map {|name, ast| "#{name} = #{ast.inspect}" }
    "<#{inner.join(" , ")}>"
  end

  def inspect_types
    inner = @fields.map {|name, ast| "#{name} = #{ast.inspect_types}" }
    "<#{inner.join(" , ")}>::#{type}"
  end
end


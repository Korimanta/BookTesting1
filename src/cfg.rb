#
# Context-Free Grammar structure.
#

require_relative 'list.rb'

class CFG
  attr_accessor :rules

  def initialize(start='*')
    @start = start
    @rules = {}
    @cache = {}
  end

  def [](token)
    @rules[token]
  end

  def []=(token, rhs)
    @cache = {}
    @rules[token] = rhs
  end

  def to_s
    @rules.sort.inject('') do |string, (lhs, rhs)|
      string + lhs + ' => ' + rhs.to_a.join('') + "\n"
    end
  end

  #
  # Expand a rule out to a string of nonterminals.
  #
  def expand(symbol='*')
    # Use the cached value if possible.
    return @cache[symbol] if @cache.key? symbol

    rhs = @rules[symbol]

    loop do
      nonterm = rhs.find { |node| node.value[0].chr == '~' }
      break if nonterm.nil?
      nonterm.value = expand nonterm.value
    end

    rhs = rhs.inject('') { |str, node| str + node.to_s }
    @cache[symbol] = rhs
  end

  def subst(nonterm, list)
    @rules.each do |lhs, rhs|
      # XXX: ~ check.
      nodes = rhs.select { |node| node.value == nonterm }
      nodes.each do |node|
        list.each_value { |str| node.ins_before str }
      end
    end
  end

  def inline(nonterm)
    rhs = @rules[nonterm]
    @rules.delete nonterm
    subst nonterm, rhs
  end

  def replace(src_symb, dst_symb)
    # If the RHS of dst_symb contains src_symb, we need inline src_symb's RHS a
    # single level to avoid creating cycles.
    # XXX: ~ check.
    src_nodes = @rules[dst_symb].select { |node| node.value == src_symb }
    src_nodes.each do |lhs_node|
      @rules[src_symb].each_value { |str| lhs_node.ins_before str }
      lhs_node.remove
    end

    @rules.delete src_symb
    subst src_symb, [ dst_symb ]
    @cache = {}
  end

  def counts
    @rules.inject(Hash.new(0)) do |counts, (lhs, rhs)|
      counts[lhs] = 2 if lhs == @start

      rhs.each do |node|
        counts[node.value] += 1 if node.value[0] == '~'
      end

      counts
    end
  end
end

class Grammar
  attr_accessor :rules, :start
  def initialize()
    # string
    @start = nil
    # string -> (GSymbol array) map
    @rules = {}
    # cache the results for expanding a var
    @expandCache = {}
  end

  def addRule(left,right)
    @rules[left] = right
    resetCache()
  end

  # replace all occurences of varold with the sequence newseq
  def substVar(varold,newseq)
    @rules.each do |curLeft,curRight|
      isChanged = false
      curRight.map! do |sym|
        if (sym.isVar && sym.token == varold)
          isChanged = true
          next newseq
        else
          next sym
        end
      end
      curRight.flatten! if isChanged
    end
  end
  # replaces all occurrences of (varold: string) with (varnew: string) and removes
  # rule for varold
  # if the rule for varnew contains a copy of varold, copy in the old rhs
  def replaceVar(varold,varnew)
    raise unless (@rules.has_key? varold and @rules.has_key? varnew)
    if(varold == @start) then @start = varnew end
    symnew = GSymbol.new(true,varnew)
    symold = GSymbol.new(true,varold)

    # annoying case where varnew contains a copy of varold
    if (@rules[varnew].include? symold)
      oldrhs = @rules[varold]
      @rules[varnew].map! do |sym|
        if (sym.isVar && sym.token == varold)
          next oldrhs
        else
          next sym
        end
      end
      @rules[varnew].flatten!
    end

    @rules.delete(varold)
    substVar(varold,[symnew])
    resetCache()
  end
  # replace varold with its rhs and remove rule for varold
  def inlineVar(varold)
    raise unless (@rules.has_key? varold)
    raise if (varold==@start)
    rhsold = @rules[varold]
    @rules.delete(varold)
    substVar(varold,rhsold)
  end

  # returns the array of terminal symbols generated by curVar : string
  def expandVar(curVar)
    raise unless (curVar.class == String)
    # if the result is already cached, use the cache
    if (@expandCache.has_key? curVar) then
      return @expandCache[curVar]
    end
    curSeq = @rules[curVar]
    nextVarInd = curSeq.index {|sym| sym.isVar}
    # recursively replace variables until only terminals left
    until nextVarInd == nil
      #nextVar : string
      nextVar = curSeq[nextVarInd].token
      repText = expandVar(nextVar)
      curSeq = curSeq.map do |sym|
        if (sym.isVar && sym.token == nextVar)
          next repText
        else
          next sym
        end
      end
      curSeq = curSeq.flatten
      nextVarInd = curSeq.index {|sym| sym.isVar}
    end
    @expandCache[curVar] = curSeq
    return curSeq
  end
  def expandAns()
    return expandVar(@start)
  end

  def resetCache()
    @expandCache = {}
  end
  def countVars
    varcount = {}
    @rules.each_key do |curleft|
      varcount[curleft] = 0
    end
    varcount[@start] = 2
    @rules.each_value do |curright|
      curright.each do |cursym|
        if(cursym.isVar) then
          varcount[cursym.token] += 1
        end
      end
    end
    return varcount
  end

  def to_s()
    out = "Start: "+@start.to_s+"\n"
    @rules.each do |curLeft,curRight|
      out += (curLeft)+":>"+(curRight.to_s)+"\n"
    end
    return out
  end

  # Begin reduction methods for making a grammar irreducible-------
  # ----------------------------------------------------------------
  # so far have only implemented rule #1 from "grammar based codes"

  def reduceGramm
    progress = true
    while progress
      progress = remSingle()
    end
  end
  def remSingle
    varcount = countVars()
    varcount.each do |curvar,curcount|
      if (curcount>1) then
        next
      else
        inlineVar(curvar)
        return true
      end
    end
    return false
  end
end
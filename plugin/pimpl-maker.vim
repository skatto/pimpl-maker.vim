scriptencoding utf-8
" Escape user settings
let s:saved_cpo = &cpo
set cpo&vim

" ------------------------------ Public variables ------------------------------

""" Class and Instance Names
let g:pimplmaker_impl_class_name = get(g:, 'pimplmaker_impl_class_name', 'Impl')
let g:pimplmaker_pimpl_instance_name = get(g:, 'pimplmaker_pimpl_instance_name', 'pimpl')

" ------------------------------ Public functions ------------------------------

""" make pimpl pattern of current (or next) class.
function! MakePimpl()
  let l:line_end_marker = '$'
  let l:Impl = g:pimplmaker_impl_class_name
  let l:pimpl = g:pimplmaker_pimpl_instance_name

  let [l:class_code, l:lnum, l:first_public_tag_line] = s:GetClassSorces(l:line_end_marker)

  let l:analyzed = s:AnalyseClassCode(l:class_code, l:line_end_marker)

  let l:class_name        = l:analyzed[0]
  let l:func_strs         = l:analyzed[1]
  let l:func_names        = l:analyzed[2]
  let l:return_type_strs  = l:analyzed[3]
  let l:footers           = l:analyzed[4]
  let l:args_strs         = l:analyzed[5]
  let l:constructors_args = l:analyzed[6]
  if get(l:analyzed, 7)
    let l:first_public_tag_line = l:analyzed[7]
  endif

  let l:indent_space = ''
  for jdx in range(&ts)
    let l:indent_space = l:indent_space.' '
  endfor

  " extend special constructors to original class.
  let l:lnum = s:ExtendSpecialConstructors(l:lnum, l:class_name, l:indent_space, l:first_public_tag_line, len(l:constructors_args) == 0)

  " make default constructor
  if len(l:constructors_args) == 0
    call add(constructors_args, '')
  endif

  " make Impl class and a pimpl member.
  let l:lnum = s:ExtendImplClassAndPimpl(l:lnum, l:Impl, l:pimpl, l:indent_space)

  " Make Impl class definition.
  let l:lnum = s:MakeImplClassDef(l:lnum, l:class_name, l:func_strs, l:line_end_marker, l:indent_space, l:Impl, l:constructors_args)

  " Make definitions of Impl member functions.
  let l:lnum = s:MakeImplFuncDef(l:lnum, l:return_type_strs, l:class_name, l:Impl, l:footers, l:line_end_marker, l:indent_space, l:constructors_args)

  let l:lines = ['',
        \'// #############################################################################',
        \'// ############################ Pointer Impl Pattern ###########################',
        \'// #############################################################################',
        \'',]

  call append(l:lnum, l:lines)
  let lnum += len(l:lines)

  " Make definitions of member constructors.
  let lnum = s:MakeOriginClassCMConDestructors(l:lnum, l:class_name, l:pimpl, l:Impl, l:constructors_args)

  " Make definitions of member functions of original class.
  let l:lnum = s:MakeOriginClassFuncDef(l:lnum, l:class_name, l:func_names, l:args_strs,
        \l:return_type_strs, l:footers, l:line_end_marker, l:indent_space, l:pimpl)

  call append(lnum, ['// #############################################################################', ''])
endfunction

" ------------------------------ Private functions -----------------------------

function! s:DelAll(expr, pat)
  let l:as = split(a:expr, a:pat)
  let l:d = ''
  for l:a in l:as
    let l:d = l:d.l:a
  endfor
  return l:d
endfunction

function! s:GetClassSorces(line_end_marker)
  let l:pos = searchpos('} *;')
  let l:pos = searchpos('\<class\>', 'b')
  let l:lnum = l:pos[0]

  let l:class_code = ''

  let l:first_public_tag_line = -1

  let l:c_blacket_n = 0
  while 1
    let l:line = getline(lnum)
    let l:class_code = l:class_code.l:line.' '.a:line_end_marker.' '
    if l:first_public_tag_line == -1 && match(l:line, 'public')
      let l:first_public_tag_line = l:lnum
    endif
    let l:c_blacket_n += len(split(' '.l:line.' ', '{')) - len(split(' '.l:line.' ', '}'))
    let l:lnum += 1
    if l:c_blacket_n == 0
      break
    endif
  endwhile
  return [l:class_code, l:lnum, l:first_public_tag_line]
endfunction

function! s:AnalyseClassCode(class_code, line_end_marker)
  let l:class_name = get(split(a:class_code, '{'), 0)
  let l:class_name = get(split(l:class_name, ':'), 0)
  let l:class_name = trim(get(split(' '.l:class_name, 'class'), 1))

  let l:search_str = '\<\([a-zA-Z0-9_][^;'.a:line_end_marker.']*[> '.a:line_end_marker.']\+\)\([a-zA-Z0-9_]\+\) *[(]\([^;]*\)[)][^;]*;'
  let l:constructor_search_str = l:class_name.' *[(]\([^;]*\)[)][^;]*;'

  let l:start = 0

  let l:func_strs = []
  let l:func_names = []
  let l:return_type_strs = []
  let l:footers = []
  let l:args_strs = []

  let l:constructors = []
  let l:constructors_args = []

  let l:spliters = ['decltype', 'noexcept', '[[']

  let l:last_constructor_line = -1
  while 1
    let l:func_str = matchstr(a:class_code, l:constructor_search_str, l:start)
    let a = l:func_str
    for spliter in l:spliters
      let a = get(split(a, spliter), 0)
    endfor
    let l:start = match(a:class_code, l:constructor_search_str, l:start)
    if l:start == -1
      break
    endif
    call add(l:constructors, matchlist(a.';', l:constructor_search_str)[0])
    call add(l:constructors_args, matchlist(a.';', l:constructor_search_str)[1])

    let l:start += strchars(l:func_str)
    let l:last_constructor_line = len(split(' '.strcharpart(a:class_code, 0, l:start).' ', '['.a:line_end_marker.']')) - 1
  endwhile

  while 1
    let l:func_str = matchstr(a:class_code, l:search_str, l:start)
    let a = l:func_str
    for spliter in l:spliters
      let a = get(split(a, spliter), 0)
    endfor
    let l:return_type = get(matchlist(a.';', l:search_str), 1)
    let l:func_name = get(matchlist(a.';', l:search_str), 2)
    let l:start = match(a:class_code, l:search_str, l:start)
    if l:start == -1
      break
    endif

    let l:start += strchars(l:func_str)

    if l:func_name == l:class_name
      continue
    endif

    call add(l:func_strs, l:func_str)
    call add(l:footers, strcharpart(l:func_str, strchars(l:return_type)))
    call add(l:return_type_strs, l:return_type)
    call add(l:func_names, l:func_name)
    call add(l:args_strs, get(matchlist(a.';', l:search_str), 3))
  endwhile

  let l:dst = [l:class_name, l:func_strs, l:func_names, l:return_type_strs, l:footers, l:args_strs, l:constructors_args]

  if last_constructor_line != -1
    let l:dst += [last_constructor_line]
  endif

  return l:dst
endfunction

function! s:ExtendSpecialConstructors(lnum, class_name, indent_space, first_public_tag_line, make_default_constructor)
  let l:lines = [
        \'',
        \a:class_name.'(const '.a:class_name.'&);',
        \a:class_name.'('.a:class_name.'&);',
        \a:class_name.'('.a:class_name.'&&);',
        \a:class_name.'& operator=(const '.a:class_name.'&);',
        \a:class_name.'& operator=('.a:class_name.'&);',
        \a:class_name.'& operator=('.a:class_name.'&&);',
        \'~'.a:class_name.'();',
        \]
  if a:make_default_constructor
    let l:lines = [a:class_name.'();'] + l:lines
  endif

  for idx in range(len(l:lines))
    let l:lines[idx] = a:indent_space.l:lines[idx]
  endfor
  let l:lines += ['']
  call append(a:first_public_tag_line + 1, l:lines)
  return a:lnum + len(l:lines)
endfunction

function! s:ExtendImplClassAndPimpl(lnum, Impl, pimpl, indent_space)
  let l:lines = [
        \'private:',
        \'class '.a:Impl.';',
        \'std::unique_ptr<'.a:Impl.'> '.a:pimpl.';'
        \]

  for idx in range(len(l:lines))
    if idx == 0
      continue
    endif
    let l:lines[idx] = a:indent_space.get(l:lines, idx)
  endfor

  call append(a:lnum - 2, l:lines)
  call append(a:lnum + 1 + len(l:lines), ['', ''])
  return a:lnum -1 + len(l:lines)
endfunction

function! s:MakeImplClassDef(lnum, class_name, func_strs, line_end_marker, indent_space, Impl, constructors_args)
  " Make Impl class definition.
  let l:impl_func_strs = []
  for str in a:func_strs
    call add(l:impl_func_strs, s:DelAll(s:DelAll(str, ' *\<override\>'), ' ['.a:line_end_marker.'] '))
  endfor

  let l:impl_constructors = []
  for l:arg in a:constructors_args
    call add(l:impl_constructors, a:Impl.'('.l:arg.');')
  endfor

  let l:lines = [
        \'',
        \'// ################################################## please move to cpp file : ',
        \'',
        \'class '.a:class_name.'::'.a:Impl.' {',
        \'public:'] + l:impl_constructors + ['', 
        \a:Impl.'(const '.a:Impl.'&) = default;',
        \a:Impl.'('.a:Impl.'&) = default;',
        \a:Impl.'('.a:Impl.'&&) = delete;',
        \a:Impl.'& operator=(const '.a:Impl.'&) = default;',
        \a:Impl.'& operator=('.a:Impl.'&) = default;',
        \a:Impl.'& operator=('.a:Impl.'&&) = delete;',
        \'~'.a:Impl.'() = default;',
        \'',
        \]
        \+ l:impl_func_strs +
        \['',
        \'private:',
        \'',
        \'};',
        \'']

  for idx in range(len(a:func_strs) + 9 + len(l:impl_constructors))
    let l:lines[idx + 5] = a:indent_space.l:lines[idx + 5]
  endfor
  call append(a:lnum, l:lines)
  return a:lnum + len(l:lines)
endfunction

function! s:MakeImplFuncDef(lnum, return_type_strs, class_name, Impl, footers, line_end_marker, indent_space, constructors_args)
  let l:lnum_dst = a:lnum

  let l:def_strs = []
  for idx in range(len(a:constructors_args))
    call add(def_strs, a:class_name.'::'.a:Impl.'::'.a:Impl.'('.a:constructors_args[idx].')  ')
  endfor
  for idx in range(len(a:return_type_strs))
    call add(l:def_strs, a:return_type_strs[idx].a:class_name.'::'.a:Impl.'::'.a:footers[idx])
  endfor

  for defs in l:def_strs
    let defs = split(defs, ' ['.a:line_end_marker.'] ')
    let def_ll = s:DelAll(get(defs, len(defs) - 1), ' *\<override\>')
    let def_ll = s:DelAll(def_ll, '\<final\>')
    let def_ll = strcharpart(def_ll, 0, strchars(def_ll) - 1).' {'
    call remove(defs, len(defs) - 1)
    call add(defs, def_ll)
    let l:buf = ''
    for l:def in defs
      let l:buf = l:buf.trim(l:def).' '
    endfor
    let defs = [trim(l:buf)]

    call add(defs, a:indent_space.'// TODO fill me.')
    call add(defs, '}')
    call add(defs, '')
    call append(l:lnum_dst, defs)
    let l:lnum_dst += len(defs)
  endfor
  return l:lnum_dst
endfunction

function! s:GetArgVarNames(args)
    let l:arg_var_names = []
    let l:move_flags = []
    for arg_str in split(a:args, ',')
      let arg_str = split(arg_str, '=')[0]
      let s = -1
      let l:arg = ''
      let l:priv_arg = 0
      let l:and = -1
      while 1
        let buf = match(arg_str, '\<[a-zA-Z0-9_]\+\>', s)
        if buf == -1
          break
        endif
        let l:priv_arg = match(arg_str, '&&', s)
        let l:and = match(arg_str, '&', l:priv_arg+2)
        let l:arg = matchlist(arg_str, '\<[a-zA-Z0-9_]\+\>', s)[0]
        let s = buf + strchars(l:arg)
      endwhile
      if l:priv_arg != -1 && match(strcharpart(arg_str, l:priv_arg), '>') == -1
        call add(l:move_flags, 1)
      elseif l:and != -1
        call add(l:move_flags, 0)
      else
        call add(l:move_flags, 1)
      endif
      call add(l:arg_var_names, l:arg)
    endfor
    return [l:arg_var_names, l:move_flags]
endfunction

function! s:GetForwardArgStr(args)
  let l:ret = s:GetArgVarNames(a:args)
  let l:arg_var_names = l:ret[0]
  let l:move_flags = l:ret[1]
  let l:dst = ''
  let f = 0
  for jdx in range(len(l:arg_var_names))
    if f == 1
      let l:dst = l:dst.', '
    endif
    let f = 1
    if l:move_flags[jdx]
      let l:dst = l:dst.'std::move('.l:arg_var_names[jdx].')'
    else
      let l:dst = l:dst.l:arg_var_names[jdx]
    endif
  endfor
    return l:dst
endfunction

function! s:MakeOriginClassCMConDestructors(lnum, class_name, pimpl, Impl, constructors_args)
  let myconstructors = []

  for l:arg in a:constructors_args
    call add(myconstructors, a:class_name.'::'.a:class_name.'('.l:arg.') : '.a:pimpl.'(std::make_unique<'.a:Impl.'>('.s:GetForwardArgStr(l:arg).')) {}')
  endfor

  let l:lines = [''] + myconstructors + ['',
        \a:class_name.'::'.a:class_name.'(const '.a:class_name.'& a) : '.a:pimpl.'(std::make_unique<'.a:Impl.'>(*a.'.a:pimpl.')) {}',
        \a:class_name.'::'.a:class_name.'('.a:class_name.'& a) : '.a:pimpl.'(std::make_unique<'.a:Impl.'>(*a.'.a:pimpl.')) {}',
        \a:class_name.'::'.a:class_name.'('.a:class_name.'&&) = default;',
        \a:class_name.'& '.a:class_name.'::operator=(const '.a:class_name.'& a) { *'.a:pimpl.' = *a.'.a:pimpl.'; }',
        \a:class_name.'& '.a:class_name.'::operator=('.a:class_name.'& a) { *'.a:pimpl.' = *a.'.a:pimpl.'; }',
        \a:class_name.'& '.a:class_name.'::operator=('.a:class_name.'&&) = default;',
        \'',
        \a:class_name.'::~'.a:class_name.'() = default;',
        \'',]
  call append(a:lnum, l:lines)
  return a:lnum + len(l:lines)
endfunction

function! s:MakeOriginClassFuncDef(lnum, class_name, func_names, args_strs, return_type_strs, footers, line_end_marker, indent_space, pimpl)
  let l:def_strs = []
  let l:lnum_dst = a:lnum

  for idx in range(len(a:return_type_strs))
    call add(l:def_strs, a:return_type_strs[idx].a:class_name.'::'.get(a:footers, idx))
  endfor

  for idx in range(len(a:return_type_strs))
    let defs = split(get(l:def_strs, idx), ' ['.a:line_end_marker.'] ')
    let def_ll = s:DelAll(get(defs, len(defs) - 1), ' *\<override\>')
    let def_ll = s:DelAll(def_ll, '\<final\>')
    let def_ll = strcharpart(def_ll, 0, strchars(def_ll) - 1).' {'
    call remove(defs, len(defs) - 1)
    call add(defs, def_ll)
    let l:buf = ''
    for l:def in defs
      let l:buf = l:buf.trim(l:def).' '
    endfor
    let defs = [trim(l:buf)]

    let l:call_line = a:indent_space.'return '.a:pimpl.'->'.a:func_names[idx].'('
    let l:call_line = l:call_line.s:GetForwardArgStr(a:args_strs[idx]).');'
    call add(defs, l:call_line)
    call add(defs, '}')
    call add(defs, '')
    call append(l:lnum_dst, defs)
    let l:lnum_dst += len(defs)
  endfor
  return l:lnum_dst
endfunction

" ---------------------------------- Commands ----------------------------------
command! MakePimpl :call MakePimpl()

" ------------------------------------------------------------------------------
" Restore user settings
let &cpo = s:saved_cpo
unlet s:saved_cpo

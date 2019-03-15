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
  let l:pos = searchpos('} *;')
  let l:pos = searchpos('\<class\>', 'b')
  let l:lnum = l:pos[0]

  let l:class_code = ''

  let l:line_end_marker = '$'

  let l:first_public_tag_line = -1

  let l:c_blacket_n = 0
  while 1
    let l:line = getline(lnum)
    let l:class_code = l:class_code.l:line.' '.l:line_end_marker.' '
    if l:first_public_tag_line == -1 && match(l:line, 'public')
      let l:first_public_tag_line = l:lnum
    endif
    let l:c_blacket_n += len(split(' '.l:line.' ', '{')) - len(split(' '.l:line.' ', '}'))
    let l:lnum += 1
    if l:c_blacket_n == 0
      break
    endif
  endwhile

  let l:class_name = get(split(l:class_code, '{'), 0)
  let l:class_name = get(split(l:class_name, ':'), 0)
  let l:class_name = trim(get(split(' '.l:class_name, 'class'), 1))

  let l:search_str = '\<\([a-zA-Z0-9_][^;'.l:line_end_marker.']*[> '.l:line_end_marker.']\+\)\([a-zA-Z0-9_]\+\) *[(]\([^;]*\)[)][^;]*;'

  let l:start = 0

  let l:func_strs = []
  let l:func_names = []
  let l:return_type_strs = []
  let l:footers = []
  let l:args_strs = []

  let l:spliters = ['decltype', 'noexcept', '[[']

  while 1
    let l:func_str = matchstr(l:class_code, l:search_str, l:start)
    let a = l:func_str
    for spliter in l:spliters
      let a = get(split(a, spliter), 0)
    endfor
    let l:return_type = get(matchlist(a.';', l:search_str), 1)
    let l:func_name = get(matchlist(a.';', l:search_str), 2)
    let l:start = match(l:class_code, l:search_str, l:start)
    if l:start == -1
      break
    endif

    call add(l:func_strs, l:func_str)
    call add(l:footers, strcharpart(l:func_str, strchars(l:return_type)))
    call add(l:return_type_strs, l:return_type)
    call add(l:func_names, l:func_name)
    call add(l:args_strs, get(matchlist(a.';', l:search_str), 3))

    let l:start += strchars(l:func_str)
  endwhile

  let l:indent_space = ''
  for jdx in range(&ts)
    let l:indent_space = l:indent_space.' '
  endfor

  let l:Impl = g:pimplmaker_impl_class_name
  let l:pimpl = g:pimplmaker_pimpl_instance_name

  " make special constructors
  let lines = [
        \l:class_name.'(const '.l:class_name.'&);',
        \l:class_name.'('.l:class_name.'&);',
        \l:class_name.'('.l:class_name.'&&);',
        \l:class_name.'& operator=(const '.l:class_name.'&);',
        \l:class_name.'& operator=('.l:class_name.'&);',
        \l:class_name.'& operator=('.l:class_name.'&&);',
        \'~'.l:class_name.'();',
        \]
  for idx in range(len(lines))
    let lines[idx] = l:indent_space.lines[idx]
  endfor
  let lines += ['']
  call append(l:first_public_tag_line + 1, lines)
  let lnum += len(lines)

  " make Impl class and a pimpl member.
  let lines = [
        \'private:',
        \'class '.l:Impl.';',
        \'std::unique_ptr<'.l:Impl.'> '.l:pimpl.';'
        \]

  for idx in range(len(lines))
    if idx == 0
      continue
    endif
    let lines[idx] = l:indent_space.get(lines, idx)
  endfor

  let lnum -= 2
  call append(lnum, lines)

  let lnum += 1 + len(lines)

  call append(lnum, ['', ''])

  " Make Impl class definition.
  let l:impl_func_strs = []
  for str in l:func_strs
    call add(l:impl_func_strs, s:DelAll(s:DelAll(str, '\<override\>'), ' '.l:line_end_marker.' '))
  endfor
  let lines = [
        \'',
        \'// ################################################## please move to cpp file : ',
        \'',
        \'class '.l:class_name.'::'.l:Impl.' {',
        \'public:',
        \l:Impl.'(const '.l:Impl.'&) = default;',
        \l:Impl.'('.l:Impl.'&) = default;',
        \l:Impl.'('.l:Impl.'&&) = delete;',
        \l:Impl.'& operator=(const '.l:Impl.'&) = default;',
        \l:Impl.'& operator=('.l:Impl.'&) = default;',
        \l:Impl.'& operator=('.l:Impl.'&&) = delete;',
        \'~'.l:Impl.'() = default;',
        \'',
        \]
        \+ l:impl_func_strs +
        \['',
        \'private:',
        \'',
        \'};',
        \'']

  for idx in range(len(l:func_strs) + 8)
    let lines[idx + 5] = l:indent_space.lines[idx + 5]
  endfor
  call append(lnum, lines)
  let lnum += len(lines)

  " Make definitions of Impl member functions.
  let l:def_strs = []

  for idx in range(len(l:return_type_strs))
    call add(l:def_strs, l:return_type_strs[idx].l:class_name.'::'.l:Impl.'::'.l:footers[idx])
  endfor

  for idx in range(len(l:return_type_strs))
    let defs = split(get(l:def_strs, idx), ' '.l:line_end_marker.' ')
    let def_ll = s:DelAll(get(defs, len(defs) - 1), '\<override\>')
    let def_ll = s:DelAll(def_ll, '\<final\>')
    let def_ll = strcharpart(def_ll, 0, strchars(def_ll) - 1).' {'
    call remove(defs, len(defs) - 1)
    call add(defs, def_ll)
    let l:buf = ''
    for l:def in defs
      let l:buf = l:buf.trim(l:def).' '
    endfor
    let defs = [trim(l:buf)]

    call add(defs, l:indent_space.'// TODO fill me.')
    call add(defs, '}')
    call add(defs, '')
    call append(lnum, defs)
    let lnum += len(defs)
  endfor

  let l:lines = ['',
        \'// #############################################################################',
        \'// ############################ Pointer Impl Pattern ###########################',
        \'// #############################################################################',
        \'',]

  call append(l:lnum, l:lines)
  let lnum += len(l:lines)

  " Make definitions of member constructors.
  let l:lines = ['',
        \l:class_name.'::'.l:class_name.'(const '.l:class_name.'& a) : '.l:pimpl.'(std::make_unique<'.l:Impl.'>(*a.'.l:pimpl.')) {}',
        \l:class_name.'::'.l:class_name.'('.l:class_name.'& a) : '.l:pimpl.'(std::make_unique<'.l:Impl.'>(*a.'.l:pimpl.')) {}',
        \l:class_name.'::'.l:class_name.'('.l:class_name.'&&) = default;',
        \l:class_name.'& '.l:class_name.'::operator=(const '.l:class_name.'& a)  { *'.l:pimpl.' = *a.'.l:pimpl.'; }',
        \l:class_name.'& '.l:class_name.'::operator=('.l:class_name.'& a)  { *'.l:pimpl.' = *a.'.l:pimpl.'; }',
        \l:class_name.'& '.l:class_name.'::operator=('.l:class_name.'&&) = default;',
        \'',
        \l:class_name.'::~'.l:class_name.'() = default;',
        \'',]
  call append(l:lnum, l:lines)
  let lnum += len(l:lines)

  " Make definitions of member functions.
  let l:def_strs = []

  for idx in range(len(l:return_type_strs))
    call add(l:def_strs, get(l:return_type_strs, idx).l:class_name.'::'.get(l:footers, idx))
  endfor

  for idx in range(len(l:return_type_strs))
    let defs = split(get(l:def_strs, idx), ' '.l:line_end_marker.' ')
    let def_ll = s:DelAll(get(defs, len(defs) - 1), '\<override\>')
    let def_ll = s:DelAll(def_ll, '\<final\>')
    let def_ll = strcharpart(def_ll, 0, strchars(def_ll) - 1).' {'
    call remove(defs, len(defs) - 1)
    call add(defs, def_ll)
    let l:buf = ''
    for l:def in defs
      let l:buf = l:buf.trim(l:def).' '
    endfor
    let defs = [trim(l:buf)]

    let l:args = []
    let l:move_flags = []
    for arg_str in split(l:args_strs[idx], ',')
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
      call add(l:args, l:arg)
    endfor

    let l:call_line = l:indent_space.'return '.l:pimpl.'->'.l:func_names[idx].'('
    let f = 0
    for jdx in range(len(l:args))
      if f == 1
        let l:call_line = l:call_line.', '
      endif
      let f = 1
      if l:move_flags[jdx]
        let l:call_line = l:call_line.'std::move('.l:args[jdx].')'
      else
        let l:call_line = l:call_line.l:args[jdx]
      endif
    endfor
    let l:call_line = l:call_line.');'
    call add(defs, l:call_line)
    call add(defs, '}')
    call add(defs, '')
    call append(lnum, defs)
    let lnum += len(defs)
  endfor
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

" ---------------------------------- Commands ----------------------------------
command! MakePimpl :call MakePimpl()

" ------------------------------------------------------------------------------
" Restore user settings
let &cpo = s:saved_cpo
unlet s:saved_cpo

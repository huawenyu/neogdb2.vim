if !exists("s:init")
    let s:init = 1
    " exists("*logger#getLogger")
    silent! let s:log = logger#getLogger(expand('<sfile>:t'))
    let s:script_path = expand('<sfile>:p:h')

    sign define GdbBreakpointEn text=● texthl=Search
    sign define GdbBreakpointDis text=● texthl=Function
    sign define GdbBreakpointDel text=● texthl=Comment

    sign define GdbCurrentLine text=☛ texthl=Error
    "sign define GdbCurrentLine text=☛ texthl=Keyword
    "sign define GdbCurrentLine text=⇒ texthl=String

    set errorformat+=#%c\ \ %.%#\ in\ %m\ \(%.%#\)\ at\ %f:%l
    set errorformat+=#%c\ \ %.%#\ in\ \ \ \ %m\ \ \ \ at\ %f:%l
    set errorformat+=#%c\ \ %m\ \(%.%#\)\ at\ %f:%l

    let s:gdb_port = 7778
    let s:breakpoint_signid_start = 5000
    let s:breakpoint_signid_max = 0
    let s:_line_sign_id = 4999

    let s:breakpoints = {}
    let s:toggle_all = 0
    let s:gdb_break_qf = '.gdb_breakpoint'
    let s:file_list = {}
    let s:prototype = {}
endif


function! neobugger#Map()
    let g:neobuggerMapTrigger        = get(g:, 'neobuggerMapTrigger',        '<f2>')

    let g:neobuggerMapRefresh        = get(g:, 'neobuggerMapRefresh',        '<f3>')
    let g:neobuggerMapContinue       = get(g:, 'neobuggerMapContinue',       '<f4>')
    let g:neobuggerMapDebugStop      = get(g:, 'neobuggerMapDebugStop',      '<S-f4>')
    let g:neobuggerMapNext           = get(g:, 'neobuggerMapNext',           '<f5>')
    let g:neobuggerMapSkip           = get(g:, 'neobuggerMapSkip',           '<S-f5>')
    let g:neobuggerMapStep           = get(g:, 'neobuggerMapStep',           '<f6>')
    let g:neobuggerMapFinish         = get(g:, 'neobuggerMapFinish',         '<S-f6>')
    let g:neobuggerMapUntil          = get(g:, 'neobuggerMapUntil',          '<f7>')
    let g:neobuggerMapEval           = get(g:, 'neobuggerMapEval',           '<f8>')
    let g:neobuggerMapWatch          = get(g:, 'neobuggerMapWatch',          '<S-f8>')
    let g:neobuggerMapToggleBreak    = get(g:, 'neobuggerMapToggleBreak',    '<f9>')
    let g:neobuggerMapRemoveBreak    = get(g:, 'neobuggerMapRemoveBreak',    '<S-f9>')
    let g:neobuggerMapToggleBreakAll = get(g:, 'neobuggerMapToggleBreakAll', '<f10>')
    let g:neobuggerMapClearBreak     = get(g:, 'neobuggerMapClearBreak',     '<S-f10>')

    let g:neobuggerMapFrameUp        = get(g:, 'neobuggerMapFrameUp',        '<a-n>')
    let g:neobuggerMapFrameDown      = get(g:, 'neobuggerMapFrameDown',      '<a-p>')


    exe 'nnoremap <silent> ' . g:neobuggerMapRefresh          . ' :VimuxRunCommand "info local"<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapContinue         . ' :VimuxRunCommand "continue"<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapNext             . ' :VimuxRunCommand "next"<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapStep             . ' :VimuxRunCommand "step"<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapSkip             . ' :VimuxRunCommand "skip"<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapFinish           . ' :VimuxRunCommand "finish"<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapUntil            . ' :VimuxRunCommand "until"<cr>'

    exe 'nnoremap <silent> ' . g:neobuggerMapToggleBreak      . ' :VimuxRunCommand "break"<cr>'

    exe 'nnoremap <silent> ' . g:neobuggerMapRemoveBreak      . ' :VimuxRunCommand "clear"<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapToggleBreakAll   . ' :ToggleAll<cr>'

    exe 'nnoremap <silent> ' . g:neobuggerMapEval             . ' :Evaluate<cr>'
    exe 'vnoremap <silent> ' . g:neobuggerMapEval             . ' :Evaluate<cr>'

    exe 'nnoremap <silent> ' . g:neobuggerMapWatch            . ' :GdbWatchWord<cr>'
    exe 'vnoremap <silent> ' . g:neobuggerMapWatch            . ' :GdbWatchRange<cr>'

    exe 'nnoremap <silent> ' . g:neobuggerMapClearBreak       . ' :ClearAll<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapDebugStop        . ' :VimuxRunCommand "stop"<cr>'

    exe 'nnoremap <silent> ' . g:neobuggerMapFrameUp          . ' :VimuxRunCommand "up"<cr>'
    exe 'nnoremap <silent> ' . g:neobuggerMapFrameDown        . ' :VimuxRunCommand "down"<cr>'
endfunction


" @args  sysinit/init  host=dut1  hostname=dut1 addr=127.0.0.1:4441
function! neobugger#Attach(...)
    if len(a:000) == 1
        let l:is_local = 1
        let l:yml_ext = "local"

        let $NEOBUGGER_FILE = a:000[0]
    elseif len(a:000) == 4
        let l:is_local = 0
        let l:yml_ext = "remote"

        let $NEOBUGGER_FILE   = a:000[0]
        let $NEOBUGGER_HOST   = a:000[1]
        let $NEOBUGGER_PROMPT = a:000[2]

        let l:addr = split(a:000[3], ":")
        let $NEOBUGGER_ADDR = l:addr[0]
        let $NEOBUGGER_PORT = l:addr[1]
    else
        echoerr "neobugger#Attach(file, host, hostname, addr:port) args error: " .. a:000
        return
    endif

    " Save cmd for next used
    call writefile(a:000, g:loaded_neogdb2)

    let l:dir = fnamemodify(s:script_path .. '/..', ':p')
    let $NEOGDB_DIR = l:dir
    let l:yml = "$HOME/.gdb.yml"
    if !filereadable(l:yml)
        let l:yml = l:dir .. 'bin/gdb_' .. l:yml_ext .. '.yml'
    endif

    if !filereadable(l:yml)
        echoerr "'gdb.yml' not exist (used by heytmux): ".. l:yml
        return
    endif

    let l:cmd = 'heytmux '.. l:yml
    let l:cmdkill = 'heytmux --kill '.. l:yml

    "let l:cmd = 'heytmux '.. shellescape(s:script_path .. '/../bin/gdb.yml')
    call system(l:cmdkill)
    let l:output = system(l:cmd)
    if v:shell_error
        echoerr "Command failed: " .. l:output
    endif
endfunction


" Constructor
" @param serveraddr
function! neobugger#New()
    let s:_wid_main = win_getid()

    " Create quickfix: lgetfile, cgetfile
    if filereadable(s:gdb_break_qf)
        exec "silent lgetfile " . s:gdb_break_qf
    endif
    "silent! lopen

    call win_gotoid(s:_wid_main)
endfunction


" @mode 0 refresh-all, 1 only-change
function! s:prototype.RefreshBreakpointSigns(mode)
    "{
    if a:mode == 0
        let i = s:breakpoint_signid_start
        while i <= s:breakpoint_signid_max
            exe 'sign unplace '.i
            let i += 1
        endwhile
    endif

    let s:breakpoint_signid_max = 0
    let id = s:breakpoint_signid_start
    for [next_key, next_val] in items(s:breakpoints)
        let buf = bufnr(next_val['file'])
        let linenr = next_val['line']

        silent! call s:log.debug("RefreshBreakpointSigns buf=" .buf)
        if buf < 0
            return
        endif

        if a:mode == 1 && next_val['change']
           \ && has_key(next_val, 'sign_id')
            exe 'sign unplace '. next_val['sign_id']
        endif

        if a:mode == 0 || (a:mode == 1 && next_val['change'])
            if next_val['state']
                exe 'sign place '.id.' name=GdbBreakpointEn line='.linenr.' buffer='.buf
            else
                exe 'sign place '.id.' name=GdbBreakpointDis line='.linenr.' buffer='.buf
            endif
            let next_val['sign_id'] = id
            let s:breakpoint_signid_max = id
            let id += 1
        endif
    endfor
    "}
endfunction


function! neobugger#Update_current_line_sign(add)
    " to avoid flicker when removing/adding the sign column(due to the change in
    " line width), we switch ids for the line sign and only remove the old line
    " sign after marking the new one
    let old_line_sign_id = s:_line_sign_id
    let s:_line_sign_id = old_line_sign_id == 4999 ? 4998 : 4999
    if a:add && s:_current_line != -1 && s:_current_buf != -1
        exe 'sign place '. s:_line_sign_id. ' name=GdbCurrentLine line='
                    \. s:_current_line. ' buffer='. s:_current_buf
    endif
    exe 'sign unplace '.old_line_sign_id
endfunction


" Firstly delete all breakpoints for Gdb delete breakpoints only by ref-no
" Then add breakpoints backto gdb
" @mode 0 reset-all, 1 enable-only-change, 2 delete-all
function! s:prototype.RefreshBreakpoints(mode)
    let is_running = 0
    if a:mode == 0 || a:mode == 2
        if self._has_breakpoints
            call self.Send('delete')
            let self._has_breakpoints = 0
        endif
    endif

    if a:mode == 0 || a:mode == 1
        let is_silent = 1
        if a:mode == 1
            let is_silent = 0
        endif

        for [next_key, next_val] in items(s:breakpoints)
            if next_val['state'] && !empty(next_val['cmd'])
                if is_silent == 1
                    let is_silent = 2
                    call self.Send('silent_on')
                endif

                if a:mode == 0 || (a:mode == 1 && next_val['change'])
                    let self._has_breakpoints = 1
                    call self.Send('break '. next_val['cmd'])
                endif
            endif
        endfor
        if is_silent == 2
            call self.Send('silent_off')
        endif
    endif

    if is_running
        call self.Send('c')
    endif
endfunction


function! neobugger#Jump(file, line)
    if !filereadable(a:file)
        return
    endif

    " Find the window IDs for the buffer named
    let buf_nr = bufnr(a:file)
    let win_ids = win_findbuf(buf_nr)
    if !empty(win_ids)
        call win_gotoid(win_ids[0])
    else
        call win_gotoid(s:_wid_main)
    endif


    let s:_current_buf = bufnr('%')
    let target_buf = bufnr(a:file, 1)
    if bufnr('%') != target_buf
        exe 'buffer ' target_buf
        let s:_current_buf = target_buf
    endif
    exe ':' a:line | m'

    let fname = fnamemodify(a:file, ':p:.')
    if !has_key(s:file_list, fname)
        let s:file_list[fname] = 1
    endif

    "let fname = fnamemodify(a:file, ':p:.')
    "exec "e ". fname
    "exec ':' a:line | m'

    if filereadable(s:gdb_break_qf)
        exec "silent lgetfile " . s:gdb_break_qf
    endif


    let s:_current_line = a:line
    call neobugger#Update_current_line_sign(1)
endfunction


function! s:prototype.Breakpoints(file)
    if self._showbreakpoint && filereadable(a:file)
        exec "silent lgetfile " . a:file
    endif
endfunction


function! s:prototype.Stack(file)
    if self._showbacktrace && filereadable(a:file)
        exec "silent! cgetfile " . a:file
    endif
endfunction


function! s:prototype.Breaks2Qf()
    let list2 = []
    let i = 0
    for [next_key, next_val] in items(s:breakpoints)
        if !empty(next_val['cmd'])
            let i += 1
            call add(list2, printf('#%d  %d in    %s    at %s:%d',
                        \ i, next_val['state'], next_val['cmd'],
                        \ next_val['file'], next_val['line']))
        endif
    endfor

    call writefile(split(join(list2, "\n"), "\n"), s:gdb_break_qf)
    if self._showbreakpoint && filereadable(s:gdb_break_qf)
        exec "silent lgetfile " . s:gdb_break_qf
    endif
endfunction


function! s:prototype.GetCFunLinenr()
  let lnum = line(".")
  let col = col(".")
  let linenr = search("^[^ \t#/]\\{2}.*[^:]\s*$", 'bW')
  call search("\\%" . lnum . "l" . "\\%" . col . "c")
  return linenr
endfunction


" Key: file:line, <or> file:function
" Value: empty, <or> if condition
" @state 0 disable 1 enable, Toggle: none -> enable -> disable
" @type 0 line-break, 1 function-break
function! s:prototype.ToggleBreak()
    let filenm = bufname("%")
    let linenr = line(".")
    let colnr = col(".")
    let cword = expand("<cword>")
    let cfuncline = self.GetCFunLinenr()

    let fname = fnamemodify(filenm, ':p:.')
    let type = 0
    if linenr == cfuncline
        let type = 1
        let file_breakpoints = fname .':'.cword
    else
        let file_breakpoints = fname .':'.linenr
    endif

    let mode = 0
    let old_value = get(s:breakpoints, file_breakpoints, {})
    if empty(old_value)
        let break_new = input("[break] ", file_breakpoints)
        if !empty(break_new)
            let old_value = {
                        \'file':fname,
                        \'type':type,
                        \'line':linenr, 'col':colnr,
                        \'fn' : '',
                        \'state' : 1,
                        \'cmd' : break_new,
                        \'change' : 1,
                        \}
            let mode = 1
            let s:breakpoints[file_breakpoints] = old_value
        endif
    elseif old_value['state']
        let break_new = input("[disable break] ", old_value['cmd'])
        if !empty(break_new)
            let old_value['state'] = 0
            let old_value['change'] = 1
        endif
    else
        let break_new = input("(delete break) ", old_value['cmd'])
        if !empty(break_new)
            call remove(s:breakpoints, file_breakpoints)
        endif
        let old_value = {}
    endif
    call self.SaveVariable(s:breakpoints, s:brk_file)
    call self.Breaks2Qf()
    call self.RefreshBreakpointSigns(mode)
    call self.RefreshBreakpoints(mode)
    if !empty(old_value)
        let old_value['change'] = 0
    endif
endfunction


function! s:prototype.ToggleBreakAll()
    let s:toggle_all = ! s:toggle_all
    let mode = 0
    for v in values(s:breakpoints)
        if s:toggle_all
            let v['state'] = 0
        else
            let v['state'] = 1
        endif
    endfor
    call self.RefreshBreakpointSigns(0)
    call self.RefreshBreakpoints(0)
endfunction


function! s:prototype.TBreak()
    let file_breakpoints = bufname('%') .':'. line('.')
    call self.Send("tbreak ". file_breakpoints. "\nc")
endfunction


function! s:prototype.ClearBreak()
    let s:breakpoints = {}
    call self.Breaks2Qf()
    call self.RefreshBreakpointSigns(0)
    call self.RefreshBreakpoints(2)
endfunction


function! s:prototype.FrameUp()
    call self.Send("up")
endfunction

function! s:prototype.FrameDown()
    call self.Send("down")
endfunction

function! s:prototype.Next()
    call self.Send("silent_on")
    call self.Send("next")
    call self.Send("silent_off")
endfunction

function! s:prototype.Step()
    call self.Send("step")
endfunction

function! s:prototype.Eval(expr)
    call self.Send(printf('print %s', a:expr))

    "" Enable smart-eval base-on the special project
    "let s:expr = a:expr
    "call self.Send(printf('whatis %s', a:expr))
endfunction


" Enable smart-eval base-on the special project
function! s:prototype.Whatis(type)
    if empty(s:expr)
        throw 'Gdb eval expr is empty'
    endif

    if has_key(self, 'Symbol')
        silent! call s:log.trace("forward to getsymbol")
        let expr = self.Symbol(a:type, s:expr)
        call self.Send(expr)
    else
        call self.Send(printf('p %s', s:expr))
    endif
    let s:expr = ""
endfunction


function! s:prototype.Watch(expr)
    let expr = a:expr
    if expr[0] != '&'
        let expr = '&' . expr
    endif

    call self.Eval(expr)
    call self.Send('watch *$')
endfunction


function! s:prototype.ParseBacktrace()
  let s:lines = readfile('/tmp/gdb.bt')
  for s:line in s:lines
    echo s:line
  endfor
endfunction


function! s:prototype.ParseVar()
  let s:lines = readfile('/tmp/gdb.bt')
  for s:line in s:lines
    echo s:line
  endfor
endfunction


function! s:prototype.on_load_bt(...)
    if self._showbacktrace && filereadable(s:gdb_bt_qf)
        exec "cgetfile " . s:gdb_bt_qf
        "call utilquickfix#RelativePath()
    endif
endfunction

function! s:prototype.on_continue(...)
    call self.Update_current_line_sign(0)
endfunction

function! s:prototype.on_jump(file, line, ...)
    let l:__func__ = "gdb.on_jump"
    silent! call s:log.info(l:__func__, ' open ', a:file, ':', a:line)

    call self.Jump(a:file, a:line)
endfunction

function! s:prototype.on_whatis(type, ...)
    call self.Whatis(a:type)
endfunction

function! s:prototype.on_parseend(...)
    call self.Whatis(a:type)
endfunction

function! s:prototype.on_retry(...)
    if self._server_exited
        return
    endif
    sleep 1
    call self.Attach()
    call self.Send('continue')
endfunction

function! s:prototype.init_gdb_env()
    " set filename-display absolute
    " set remotetimeout 50
    let cmdstr = "set confirm off\n
                \ set pagination off\n
                \ set width 0\n
                \ set verbose off\n
                \ set logging off\n
                \ handle SIGUSR2 noprint nostop\n
                \ set print elements 2048\n
                \ set print pretty on\n
                \ set print array off\n
                \ set print array-indexes on\n
                \"
    call self.Send(cmdstr)

    let cmdstr = "define parser_bt\n
                \ set logging off\n
                \ set logging file /tmp/gdb.bt\n
                \ set logging overwrite on\n
                \ set logging redirect on\n
                \ set logging on\n
                \ bt\n
                \ set logging off\n
                \ echo neobugger_parseend\n
                \ end"
    call self.Send(cmdstr)

    let cmdstr = "define parser_var_bt\n
                \ set logging off\n
                \ set logging file /tmp/gdb.bt\n
                \ set logging overwrite on\n
                \ set logging redirect on\n
                \ set logging on\n
                \ bt\n
                \ set logging off\n
                \ set logging file /tmp/gdb.var\n
                \ set logging overwrite on\n
                \ set logging redirect on\n
                \ set logging on\n
                \ info local\n
                \ set logging off\n
                \ echo neobugger_parseend\n
                \ end"
    call self.Send(cmdstr)

    let cmdstr = "define silent_on\n
                \ set logging off\n
                \ set logging file /dev/null\n
                \ set logging overwrite off\n
                \ set logging redirect on\n
                \ set logging on\n
                \ end"
    call self.Send(cmdstr)

    let cmdstr = "define silent_off\n
                \ set logging off\n
                \ end"
    call self.Send(cmdstr)

    let cmdstr = "define hook-stop\n
                \ handle SIGALRM nopass\n
                \ parser_bt\n
                \ end\n
                \ \n
                \ define hook-run\n
                \ handle SIGALRM pass\n
                \ end\n
                \ \n
                \ define hook-continue\n
                \ handle SIGALRM pass\n
                \ \n
                \ end"
    call self.Send(cmdstr)

endfunction

function! s:prototype._focus_main()
    let cwindow = win_getid()
    if cwindow != g:gdbserver._wid_main
        if win_gotoid(g:gdbserver._wid_main) != 1
            stopinsert
            return
        endif
    endif
    stopinsert
endfunction

function! s:prototype.on_init(...)
    let l:__func__ = "gdb.on_init"
    silent! call s:log.info(l:__func__, " args=", string(a:000))

    if self._initialized
      silent! call s:log.warn(l:__func__, "() ignore re-initial!")
      return
    endif

    let self._initialized = 1
    let self._autorun = 0
    "call self.init_gdb_env()


    " Load all files from backtrace to solve relative-path
    call self._focus_main()
    silent! call s:log.trace("Load open files ...")
    silent! call s:log.trace("  try open files from ". s:fl_file)
    if filereadable(s:fl_file)
        call self.ReadVariable("s:file_list", s:fl_file)
        for [next_key, next_val] in items(s:file_list)
            if filereadable(next_key)
                exec "e ". fnamemodify(next_key, ':p:.')
            endif
        endfor
    endif

    silent! call s:log.info("Load breaks ...")
    if filereadable(s:brk_file)
        call self.ReadVariable("s:breakpoints", s:brk_file)
    endif

    silent! call s:log.info("Load set breaks ...")
    call self._focus_main()
    if !empty(s:breakpoints)
        call self.Breaks2Qf()
    silent! call s:log.info("Load set breaks2 ...")
        call self.RefreshBreakpointSigns(0)
    silent! call s:log.info("Load set breaks3 ...")
        call self.RefreshBreakpoints(0)
    silent! call s:log.info("Load set breaks4 ...")
    endif

    if has_key(self, 'Init')
        silent! call s:log.info(l:__func__, " call Init()")
        "call neobugger#Handle(s:module, self.Init)
        call self.Init()
    else
        silent! call s:log.info(l:__func__, " Init() is null.")
    endif

    if self._autorun
        let l:cmdstr = ""
        if self._mode ==# 'local'
            let l:cmdstr = "br main\n
                        \ r"
            call self.Send(l:cmdstr)
        elseif self._mode ==# 'pid'
            let l:cmdstr = "attach ". self._attach_pid
            call self.Send(l:cmdstr)

            let l:cmdstr = "symbol-file ". self._binaryFile
            call self.Send(l:cmdstr)

            " hint backtrace
            call self.Send("bt")
        endif
    endif
endfunction


function! s:prototype.on_accept(port, ...)
    if a:port
        let self._server_addr[1] = a:port
        call self.Attach()
    endif
endfunction


function s:prototype.on_remote_debugging(...)
    let self._remote_debugging = 1
endfunction


function! s:prototype.on_remoteconn_succ(...)
    let self._remote_debugging = 1
endfunction


function! s:prototype.on_remoteconn_fail(...)
    silent! call s:log.error("Remote connect gdbserver fail!")
endfunction


function! s:prototype.on_pause(...)
    let self._remote_debugging = 1
endfunction


function! s:prototype.on_disconnected(...)
    if !self._server_exited && self._reconnect
        " Refresh to force a delete of all watchpoints
        "call self.RefreshBreakpoints(2)
        sleep 1
        call self.Attach()
        call self.Send('continue')
    endif
endfunction

function! s:prototype.on_exit(...)
    let self._server_exited = 1
endfunction


function! s:prototype.view_source(...)
    let self._remote_debugging = 1
endfunction

function! s:prototype.view_breakpoint(...)
    let self._remote_debugging = 1
endfunction

function! s:prototype.view_stack(...)
    let self._remote_debugging = 1
endfunction



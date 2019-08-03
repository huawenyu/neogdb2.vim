if exists("g:loaded_neovim_gdb") || &cp
    finish
endif
let g:loaded_neovim_gdb = 1

if has("nvim")
else
    finish
endif

" InstanceGdb {{{1
command! -nargs=+ GdbStart          call neobugger#gdb#New(<f-args>)
command! -nargs=+ GdbUpdate         call neobugger#gdb#Update(<f-args>)
command! -nargs=+ GdbEvent          call neobugger#gdb#Handle('Event', <f-args>)

command! -nargs=0 GdbDebugStop      call neobugger#gdb#Handle('Kill')
command! -nargs=0 GdbToggleBreak    call neobugger#gdb#Handle('ToggleBreak')
command! -nargs=0 GdbToggleBreakAll call neobugger#gdb#Handle('ToggleBreakAll')
command! -nargs=0 GdbClearBreak     call neobugger#gdb#Handle('ClearBreak')
command! -nargs=0 GdbContinue       call neobugger#gdb#Handle('Send',  'continue')
command! -nargs=0 GdbNext           call neobugger#gdb#Handle('Next')
command! -nargs=0 GdbStep           call neobugger#gdb#Handle('Step')
command! -nargs=0 GdbFinish         call neobugger#gdb#Handle('Send',  "finish")
command! -nargs=0 GdbUntil          call neobugger#gdb#Handle('TBreak')
command! -nargs=0 GdbFrameUp        call neobugger#gdb#Handle('FrameUp')
command! -nargs=0 GdbFrameDown      call neobugger#gdb#Handle('FrameDown')
command! -nargs=0 GdbInterrupt      call neobugger#gdb#Handle('Interrupt')
command! -nargs=0 GdbRefresh        call neobugger#gdb#Handle('Send',  "info line")
command! -nargs=0 GdbInfoLocal      call neobugger#gdb#Handle('Send',  "info local")
command! -nargs=0 GdbInfoBreak      call neobugger#gdb#Handle('Send',  "info break")
command! -nargs=0 GdbEvalWord       call neobugger#gdb#Handle('Eval',  expand('<cword>'))
command! -nargs=0 GdbWatchWord      call neobugger#gdb#Handle('Watch', expand('<cword>')

command! -range -nargs=0 GdbEvalRange  call neobugger#gdb#Handle('Eval',  nelib#util#get_visual_selection())
command! -range -nargs=0 GdbWatchRange call neobugger#gdb#Handle('Watch', nelib#util#get_visual_selection())
" }}}


" Keymap options {{{1
"
if exists('g:neobugger_leader') && !empty(g:neobugger_leader)
        let g:gdb_keymap_refresh = g:neobugger_leader.'r'
        let g:gdb_keymap_continue = g:neobugger_leader.'c'
        let g:gdb_keymap_next = g:neobugger_leader.'n'
        let g:gdb_keymap_step = g:neobugger_leader.'i'
        let g:gdb_keymap_finish = g:neobugger_leader.'N'
        let g:gdb_keymap_until = g:neobugger_leader.'t'
        let g:gdb_keymap_toggle_break = g:neobugger_leader.'b'
        let g:gdb_keymap_toggle_break_all = g:neobugger_leader.'a'
        let g:gdb_keymap_clear_break = g:neobugger_leader.'C'
        let g:gdb_keymap_debug_stop = g:neobugger_leader.'x'
        let g:gdb_keymap_frame_up = g:neobugger_leader.'k'
        let g:gdb_keymap_frame_down = g:neobugger_leader.'j'
else
    if !exists("g:gdb_keymap_refresh")
        let g:gdb_keymap_refresh = '<f3>'
    endif
    if !exists("g:gdb_keymap_continue")
        let g:gdb_keymap_continue = '<f4>'
    endif
    if !exists("g:gdb_keymap_next")
        let g:gdb_keymap_next = '<f5>'
    endif
    if !exists("g:gdb_keymap_step")
        let g:gdb_keymap_step = '<f6>'
    endif
    if !exists("g:gdb_keymap_finish")
        let g:gdb_keymap_finish = '<f7>'
    endif
    if !exists("g:gdb_keymap_until")
        let g:gdb_keymap_until = '<f8>'
    endif
    if !exists("g:gdb_keymap_toggle_break")
        let g:gdb_keymap_toggle_break = '<f9>'
    endif
    if !exists("g:gdb_keymap_toggle_break_all")
        let g:gdb_keymap_toggle_break_all = '<f10>'
    endif
    if !exists("g:gdb_keymap_clear_break")
        let g:gdb_keymap_clear_break = '<f21>'
    endif
    if !exists("g:gdb_keymap_debug_stop")
        let g:gdb_keymap_debug_stop = '<f17>'
    endif

    if !exists("g:gdb_keymap_frame_up")
        let g:gdb_keymap_frame_up = '<c-n>'
    endif

    if !exists("g:gdb_keymap_frame_down")
        let g:gdb_keymap_frame_down = '<c-p>'
    endif

endif
" }}}


" Customization options {{{1
"
if !exists("g:neobugger_addr")
    let g:neobugger_addr = '/tmp/nvim.gdb'
endif
if !exists("g:gdb_require_enter_after_toggling_breakpoint")
    let g:gdb_require_enter_after_toggling_breakpoint = 0
endif

if !exists("g:restart_app_if_gdb_running")
    let g:restart_app_if_gdb_running = 1
endif

if !exists("g:neobugger_other")
    let g:neobugger_other = 1
endif

" }}}


" Helper options {{{1
let s:gdb_local_remote = 0
function! NeobuggerCommandStr()
    if s:gdb_local_remote
        let s:gdb_local_remote = 0
        if exists("g:neogdb_attach_remote_str")
            return 'Nbgdbattach '. g:neogdb_attach_remote_str
        else
            return 'Nbgdbattach sysinit/init 192.168.0.180:444'
        endif
    else
        let s:gdb_local_remote = 1
        return 'GdbStart /tmp/nvim.gdb'
    endif
endfunction

nnoremap <F2> :<c-u><C-\>e NeobuggerCommandStr()<cr>
cnoremap <F2> :<c-u><C-\>e NeobuggerCommandStr()<cr>
" }}}


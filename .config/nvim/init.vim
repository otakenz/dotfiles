set runtimepath^=~/.vim
set runtimepath+=~/.vim/after

let &packpath=&runtimepath
source ~/.vimrc

let g:python3_host_prog = '~/.asdf/installs/python/3.8.10/bin/python'

" .............................................................................
" nvim-treesitter/nvim-treesitter
" .............................................................................

" Toggle highlight
map <Leader><F1> :TSToggle highlight<CR>

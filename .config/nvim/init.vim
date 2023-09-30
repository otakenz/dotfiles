set runtimepath^=~/.vim
set runtimepath+=~/.vim/after

let &packpath=&runtimepath
source ~/.vimrc

" Fix Treesitter syntax error highlighting
" https://github.com/nvim-treesitter/nvim-treesitter/issues/78
hi! link @error Normal

" .............................................................................
" nvim-treesitter/nvim-treesitter
" .............................................................................

" Toggle highlight
map <Leader><F1> :TSToggle highlight<CR>

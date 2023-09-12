" Run :TSInstall <language_to_install> (:TSInstallInfo)
" If plugin is updated, parser also have to, run :TSUpdate
Plug 'nvim-treesitter/nvim-treesitter', { 'do': ':TSUpdate' }


" Dart support
Plug 'dart-lang/dart-vim-plugin'
Plug 'natebosch/dartlang-snippets'

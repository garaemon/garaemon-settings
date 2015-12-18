cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing ghq]"
go get github.com/motemen/ghq

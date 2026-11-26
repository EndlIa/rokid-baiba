// 把 Promise 套上超时，超时抛带阶段名的错误
// 计时器无论成败都会清掉，避免残留定时器
export function raceTimeout(promise, ms, label) {
  let timer = null
  const guard = new Promise(function (resolve, reject) {
    timer = setTimeout(function () {
      const error = new Error(label + '超时')
      error.stage = label
      reject(error)
    }, ms)
  })
  return Promise.race([promise, guard]).then(
    function (value) {
      if (timer) clearTimeout(timer)
      return value
    },
    function (error) {
      if (timer) clearTimeout(timer)
      throw error
    }
  )
}

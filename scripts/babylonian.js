const reaper = require("../src/ReaperSDK.js");

async function main() {

  let Root = await ethers.getContractFactory("babylon");
  let root = await Root.deploy();

  let aggreagate;

  for(let i=1; i<208; i++) {
    let a = i;

    let b  = (((a)) / Math.sqrt(300+((a))**2));
    let c = b - 70;
    console.log(b);
    /*
    a = await root.div(a, 100);

    let x = a - 50;
    console.log(x.toString());
    let y = await root.sqrt(300+(x**2));
    console.log(y.toString());
    let z = await root.div(x, y);
    console.log(z.toString());
    let curve = (z + 1) * 5;
    */

  //  console.log(`day ${i*10} multiplier: ${(curve*5).toString()}`);

/*

    let b = await root.sqrt(a);
    let c = await root.sqrt(b);
    let r = await root.div(c*100000000, 24800);
    //console.log("b "+b.toString());
    //console.log("c "+c.toString());
    //console.log("r "+r.toString());

    let b2 = await root.div(a, 800);
    let c2 = await root.sqrt(b2);
    let r2 = await root.div(c2*100000000, 60000);
    //console.log("b2 "+b2.toString());
    //console.log("c2 "+c2.toString());
    //console.log("r2 "+r2.toString());

    let final = await root.min(r, r2);
    //console.log("final "+final.toString());
    console.log(`day ${i*10} multiplier: ${final/10000}`);
*/

  }




}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });

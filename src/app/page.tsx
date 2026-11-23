import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import Hero from "@/components/home/Hero";
import Bento from "@/components/home/Bento";
import Overview from "@/components/home/Overview";

export default function Home() {
  return (
    <>
      <Nav />
      <main id="main">
        <Hero />
        <Bento />
        <Overview />
      </main>
      <Footer />
    </>
  );
}

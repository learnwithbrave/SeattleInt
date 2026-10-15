import { motion, type Variants } from 'framer-motion'
import { useSiteContent } from '../content/siteContentStore'
import { useDocumentMeta } from '../hooks/useDocumentMeta'

const fadeInUp: Variants = {
  hidden: { opacity: 0, y: 30 },
  show: { opacity: 1, y: 0, transition: { duration: 0.8, ease: "easeOut" } }
}

const staggerContainer: Variants = {
  hidden: { opacity: 0 },
  show: { opacity: 1, transition: { staggerChildren: 0.1 } }
}

export function AboutPage() {
  const siteContent = useSiteContent()
  useDocumentMeta(
    'About',
    'Meet Seattle International Church through our mission, vision, values, statement of faith, story, and leadership team.',
  )

  return (
    <div className="flex flex-col bg-white">
      {/* Cinematic Hero */}
      <section className="relative w-full pt-48 pb-32 flex flex-col justify-center bg-stone-900 text-white isolate overflow-hidden">
        <img 
          src="https://images.unsplash.com/photo-1510590337019-5ef8d3d32116?q=80&w=2000&auto=format&fit=crop" 
          className="absolute inset-0 w-full h-full object-cover opacity-20 mix-blend-overlay" 
          alt="Church interior" 
        />
        <div className="absolute inset-0 bg-gradient-to-t from-stone-900 via-stone-900/60 to-transparent pointer-events-none" />
        
        <div className="relative z-10 w-full max-w-[1400px] mx-auto px-6 md:px-16">
          <motion.div 
            initial="hidden"
            animate="show"
            variants={staggerContainer}
            className="max-w-3xl"
          >
            <motion.p variants={fadeInUp} className="text-primary-500 font-bold uppercase tracking-[0.2em] text-xs mb-4">
              About us
            </motion.p>
            <motion.h1 variants={fadeInUp} className="font-display text-5xl md:text-7xl font-bold leading-[1.1] mb-6">
               Who we are and what shapes our church family
            </motion.h1>
            <motion.p variants={fadeInUp} className="text-xl text-stone-300 font-medium max-w-2xl leading-relaxed">
              We want this church to feel spiritually grounded, practically welcoming,
              and transparent about what we believe.
            </motion.p>
          </motion.div>
        </div>
      </section>

      {/* Mission & Vision */}
      <section className="py-24 px-6 md:px-16 max-w-[1400px] mx-auto w-full grid grid-cols-1 md:grid-cols-2 gap-8 -mt-16 relative z-20">
        <motion.article 
          whileHover={{ y: -5 }}
          className="bg-white p-10 md:p-14 shadow-2xl shadow-stone-900/5 border border-stone-100 flex flex-col"
        >
          <p className="text-primary-500 font-bold uppercase tracking-widest text-xs mb-4">Mission</p>
          <h2 className="font-display text-3xl font-bold text-stone-900 mb-6">What we are committed to</h2>
          <p className="text-stone-600 leading-relaxed text-lg italic border-l-4 border-primary-500 pl-6">
            "{siteContent.about.mission}"
          </p>
        </motion.article>

        <motion.article 
          whileHover={{ y: -5 }}
          className="bg-white p-10 md:p-14 shadow-2xl shadow-stone-900/5 border border-stone-100 flex flex-col"
        >
          <p className="text-primary-500 font-bold uppercase tracking-widest text-xs mb-4">Vision</p>
          <h2 className="font-display text-3xl font-bold text-stone-900 mb-6">Where we are headed</h2>
          <p className="text-stone-600 leading-relaxed text-lg">
            {siteContent.about.vision}
          </p>
        </motion.article>
      </section>

      {/* Core Values */}
      <section className="py-24 bg-stone-50 overflow-hidden">
        <div className="max-w-[1400px] mx-auto px-6 md:px-16 w-full flex flex-col">
          <div className="mb-16">
            <p className="text-stone-400 font-bold uppercase tracking-[0.2em] text-xs mb-4">Core Values</p>
            <h2 className="font-display text-4xl font-bold text-stone-900">Practices that shape our culture</h2>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            {siteContent.about.values.map((value, idx) => (
              <motion.article 
                key={value}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: idx * 0.1 }}
                className="bg-white p-8 border border-stone-100 shadow-sm flex items-start gap-4"
              >
                <div className="shrink-0 w-8 h-8 bg-primary-50 text-primary-600 rounded-full flex items-center justify-center font-bold text-xs">
                  {idx + 1}
                </div>
                <p className="text-stone-800 font-medium leading-relaxed">{value}</p>
              </motion.article>
            ))}
          </div>
        </div>
      </section>

      <section className="py-24 px-6 md:px-16 max-w-[1400px] mx-auto w-full grid grid-cols-1 lg:grid-cols-2 gap-16">
        {/* Statement of Faith */}
        <article>
          <div className="mb-12">
            <p className="text-stone-400 font-bold uppercase tracking-[0.2em] text-xs mb-4">Statement of faith</p>
            <h2 className="font-display text-3xl font-bold text-stone-900">What we believe</h2>
          </div>
          <ul className="flex flex-col gap-6">
            {siteContent.about.statementOfFaith.map((item, idx) => (
              <li key={item} className="flex gap-4 group">
                <span className="text-primary-500 font-display font-bold text-xl opacity-20 group-hover:opacity-100 transition-opacity translate-y-[-2px]">0{idx + 1}</span>
                <p className="text-stone-600 leading-relaxed">{item}</p>
              </li>
            ))}
          </ul>
        </article>

        {/* Our Story */}
        <article>
          <div className="mb-12">
            <p className="text-stone-400 font-bold uppercase tracking-[0.2em] text-xs mb-4">Our story</p>
            <h2 className="font-display text-3xl font-bold text-stone-900">How the church has grown</h2>
          </div>
          <div className="flex flex-col gap-8 relative pl-8 border-l border-stone-200">
            {siteContent.about.history.map((item) => (
              <div key={item} className="relative">
                <div className="absolute left-[-37px] top-1 w-4 h-4 rounded-full bg-white border-2 border-primary-500 z-10" />
                <p className="text-stone-600 leading-relaxed">{item}</p>
              </div>
            ))}
          </div>
        </article>
      </section>

      {/* Leadership */}
      <section className="py-24 bg-stone-900 text-white isolate overflow-hidden relative">
        <div className="absolute top-[-20%] right-[-10%] w-[600px] h-[600px] bg-primary-500/10 rounded-full blur-[120px] pointer-events-none" />
        
        <div className="max-w-[1400px] mx-auto px-6 md:px-16 w-full flex flex-col items-center">
          <div className="mb-16 text-center">
            <p className="text-primary-500 font-bold uppercase tracking-[0.2em] text-xs mb-4">Leadership</p>
            <h2 className="font-display text-4xl md:text-5xl font-bold">Meet the team serving the church</h2>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 w-full">
            {siteContent.leaders.map((leader, idx) => (
              <motion.article 
                key={leader.email}
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: idx * 0.1, duration: 0.6 }}
                className="bg-white/5 backdrop-blur-sm p-8 border border-white/10 hover:border-white/20 transition-colors group"
              >
                <div className="w-16 h-16 bg-white/10 text-white font-display font-bold text-xl flex items-center justify-center mb-6 group-hover:bg-primary-500 transition-colors">
                  {leader.name.split(' ').map(n => n[0]).slice(0, 2).join('')}
                </div>
                <p className="text-primary-500 font-bold uppercase tracking-widest text-[10px] mb-2">{leader.role}</p>
                <h3 className="font-display text-2xl font-bold mb-4">{leader.name}</h3>
                <p className="text-white/60 text-sm leading-relaxed mb-6 line-clamp-3">{leader.bio}</p>
                
                <div className="flex flex-col gap-2 pt-6 border-t border-white/10">
                  <span className="text-xs font-bold text-white/40 uppercase tracking-widest">{leader.focus}</span>
                  <a href={`mailto:${leader.email}`} className="text-sm text-primary-400 hover:text-white transition-colors">{leader.email}</a>
                </div>
              </motion.article>
            ))}
          </div>
        </div>
      </section>
    </div>
  )
}
